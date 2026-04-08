import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';

const DEFAULT_TIMEOUT_MS = 60_000;
const COMPANION_ROOT = 'C:/Users/1/.claude/plugins/cache/openai-codex/codex';
const COMPANION_RELATIVE_PATH = 'scripts/codex-companion.mjs';

// ORCH_MCP_DEPTH cycle guard (docs/mcp-servers.md #6).
// Each MCP server reads its inherited depth, refuses to start a new agent
// run when depth >= limit, and injects depth+1 into the spawned companion's
// env so it propagates down the chain. Default limit 2 allows
// Claude→A→B (2 hops) but blocks Claude→A→B→A.
const DEPTH_LIMIT_DEFAULT = 2;

function currentDepth() {
  const raw = process.env.ORCH_MCP_DEPTH;
  if (raw == null || raw === '') {
    return 0;
  }
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

function depthLimit() {
  const raw = process.env.ORCH_MCP_DEPTH_LIMIT;
  if (raw == null || raw === '') {
    return DEPTH_LIMIT_DEFAULT;
  }
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : DEPTH_LIMIT_DEFAULT;
}

function enforceDepthLimit(toolName) {
  const depth = currentDepth();
  const limit = depthLimit();
  if (depth >= limit) {
    throw new Error(
      `ORCH_MCP_DEPTH limit exceeded: depth=${depth}, limit=${limit}. ` +
      `Refusing to invoke ${toolName} to prevent MCP cycle. ` +
      `Override with ORCH_MCP_DEPTH_LIMIT on the top-level orchestrator if intentional.`
    );
  }
}

function parseSemver(version) {
  const match = /^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$/.exec(version);
  if (!match) {
    return null;
  }
  return match.slice(1, 4).map((part) => Number(part));
}

function compareSemverDesc(left, right) {
  const a = parseSemver(left);
  const b = parseSemver(right);
  if (!a && !b) {
    return right.localeCompare(left);
  }
  if (!a) {
    return 1;
  }
  if (!b) {
    return -1;
  }
  for (let index = 0; index < 3; index += 1) {
    if (a[index] !== b[index]) {
      return b[index] - a[index];
    }
  }
  return right.localeCompare(left);
}

function ensureExistingFile(filePath, messagePrefix) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`${messagePrefix}: ${filePath}`);
  }
  return filePath;
}

export function resolveCompanionPath() {
  const envPath = process.env.CODEX_COMPANION_PATH;
  if (envPath) {
    return ensureExistingFile(envPath, 'CODEX_COMPANION_PATH does not point to an existing file');
  }

  if (!fs.existsSync(COMPANION_ROOT)) {
    throw new Error(`Codex companion base directory not found: ${COMPANION_ROOT}`);
  }

  const versionDirs = fs
    .readdirSync(COMPANION_ROOT, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .filter((name) => parseSemver(name) != null)
    .sort(compareSemverDesc);

  for (const version of versionDirs) {
    const candidate = path.join(COMPANION_ROOT, version, COMPANION_RELATIVE_PATH);
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }

  throw new Error(`No codex-companion.mjs found under ${COMPANION_ROOT}`);
}

export function runCompanion(subcommand, args = [], opts = {}) {
  const companionPath = resolveCompanionPath();
  const cwd = opts.cwd ?? process.cwd();
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  // Workaround for upstream codex-companion bug (1.0.3 scripts/lib/process.mjs):
  // its runCommand() does `shell: process.env.SHELL || true`. When SHELL points
  // to Git Bash on Windows, MSYS path-converts taskkill flags like "/PID /T /F"
  // into "C:/Program Files/Git/PID ..." and `cancel` fails. Stripping SHELL
  // forces the cmd.exe fallback (no MSYS conversion). Safe across all
  // companion subcommands — they don't depend on bash builtins.
  const childEnv = { ...process.env };
  if (process.platform === 'win32') {
    delete childEnv.SHELL;
  }
  // Propagate cycle-guard depth to companion (and any MCP child it spawns).
  childEnv.ORCH_MCP_DEPTH = String(currentDepth() + 1);

  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [companionPath, subcommand, ...args], {
      cwd,
      env: childEnv,
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });

    let stdout = '';
    let stderr = '';
    let finished = false;

    const timer = setTimeout(() => {
      if (finished) {
        return;
      }
      finished = true;
      child.kill();
      reject(new Error(`codex-companion ${subcommand} timed out after ${timeoutMs}ms`));
    }, timeoutMs);

    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');

    child.stdout.on('data', (chunk) => {
      stdout += chunk;
    });

    child.stderr.on('data', (chunk) => {
      stderr += chunk;
    });

    child.on('error', (error) => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(timer);
      reject(error);
    });

    child.on('close', (code) => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(timer);

      const trimmedStdout = stdout.trim();
      const trimmedStderr = stderr.trim();

      if (code !== 0) {
        const detail = trimmedStderr || trimmedStdout || `exit code ${code}`;
        reject(new Error(`codex-companion ${subcommand} failed: ${detail}`));
        return;
      }

      if (!trimmedStdout) {
        resolve({});
        return;
      }

      try {
        resolve(JSON.parse(trimmedStdout));
      } catch {
        resolve({ raw: trimmedStdout });
      }
    });
  });
}

function assertAbsoluteCwd(cwd) {
  if (cwd == null) {
    return;
  }
  if (!path.isAbsolute(cwd)) {
    throw new Error(`cwd must be an absolute path: ${cwd}`);
  }
}

function extractJobId(payload) {
  if (payload && typeof payload === 'object' && typeof payload.jobId === 'string' && payload.jobId) {
    return payload.jobId;
  }
  if (payload && typeof payload === 'object' && typeof payload.raw === 'string') {
    const match = payload.raw.match(/\b(task-[a-z0-9-]+|job-[a-z0-9-]+)\b/i);
    if (match) {
      return match[1];
    }
  }
  throw new Error('Unable to extract jobId from codex-companion task output');
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function readCodexStatusValue(payload) {
  if (!payload || typeof payload !== 'object') {
    return null;
  }

  if (payload.job && typeof payload.job === 'object' && typeof payload.job.status === 'string') {
    return payload.job.status.toLowerCase();
  }

  if (typeof payload.status === 'string') {
    return payload.status.toLowerCase();
  }

  if (typeof payload.raw === 'string') {
    const raw = payload.raw.toLowerCase();
    if (raw.includes('completed')) {
      return 'completed';
    }
    if (raw.includes('failed')) {
      return 'failed';
    }
    if (raw.includes('cancelled')) {
      return 'cancelled';
    }
    if (raw.includes('error')) {
      return 'error';
    }
  }

  return null;
}

export async function codexTask({ prompt, write = false, model, effort, resume = false, fresh = false, cwd }) {
  enforceDepthLimit('codex_task');

  if (resume && fresh) {
    throw new Error('Choose either resume or fresh, not both.');
  }

  assertAbsoluteCwd(cwd);

  const args = ['--background', '--json'];

  if (write) {
    args.push('--write');
  }
  if (resume) {
    args.push('--resume-last');
  }
  if (fresh) {
    args.push('--fresh');
  }
  if (model === 'spark') {
    args.push('--model', 'spark');
  }
  if (effort) {
    args.push('--effort', effort);
  }
  if (cwd) {
    args.push('--cwd', cwd);
  }
  if (prompt) {
    args.push(prompt);
  }

  const payload = await runCompanion('task', args, { cwd: cwd ?? process.cwd() });
  return {
    ...payload,
    jobId: extractJobId(payload)
  };
}

export async function codexStatus({ jobId } = {}) {
  const args = ['--json'];
  if (jobId) {
    args.unshift(jobId);
  }
  return runCompanion('status', args);
}

export async function codexResult({ jobId }) {
  return runCompanion('result', [jobId, '--json']);
}

export async function codexCancel({ jobId }) {
  return runCompanion('cancel', [jobId, '--json']);
}

export async function codexRun(input) {
  enforceDepthLimit('codex_run');

  const {
    pollIntervalMs = 2000,
    timeoutMs = 600000,
    ...taskInput
  } = input;

  const startedAt = Date.now();
  const task = await codexTask(taskInput);
  const { jobId } = task;
  let polls = 0;

  while (Date.now() - startedAt < timeoutMs) {
    polls += 1;
    const statusPayload = await codexStatus({ jobId });
    const status = readCodexStatusValue(statusPayload);

    if (status === 'completed') {
      const result = await codexResult({ jobId });
      return {
        jobId,
        status: 'completed',
        elapsedMs: Date.now() - startedAt,
        result,
        polls
      };
    }

    if (status === 'failed' || status === 'cancelled' || status === 'error') {
      const result = await codexResult({ jobId });
      return {
        jobId,
        status: 'failed',
        elapsedMs: Date.now() - startedAt,
        result,
        polls
      };
    }

    await sleep(pollIntervalMs);
  }

  return {
    jobId,
    status: 'timeout',
    elapsedMs: Date.now() - startedAt,
    result: null,
    polls
  };
}
