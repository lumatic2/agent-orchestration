import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';

const DEFAULT_TIMEOUT_MS = 60_000;
const FOREGROUND_TIMEOUT_MS = 15 * 60_000;
const COMPANION_ROOT = 'C:/Users/1/.claude/plugins/cache/claude-gemini-plugin/gemini';
const COMPANION_RELATIVE_PATH = 'scripts/gemini-companion.mjs';

// ORCH_MCP_DEPTH cycle guard (docs/mcp-servers.md #6).
// Mirrors codex-mcp/src/codex-exec.mjs — see that file for the rationale.
// Default limit 2 allows Claude→A→B but blocks Claude→A→B→A.
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
  const envPath = process.env.GEMINI_COMPANION_PATH;
  if (envPath) {
    return ensureExistingFile(envPath, 'GEMINI_COMPANION_PATH does not point to an existing file');
  }

  if (!fs.existsSync(COMPANION_ROOT)) {
    throw new Error(`Gemini companion base directory not found: ${COMPANION_ROOT}`);
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

  throw new Error(`No gemini-companion.mjs found under ${COMPANION_ROOT}`);
}

export function runCompanion(subcommand, args = [], opts = {}) {
  const companionPath = resolveCompanionPath();
  const cwd = opts.cwd ?? process.cwd();
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  // Propagate cycle-guard depth to companion (and any MCP child it spawns).
  const childEnv = { ...process.env, ORCH_MCP_DEPTH: String(currentDepth() + 1) };

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
      reject(new Error(`gemini-companion ${subcommand} timed out after ${timeoutMs}ms`));
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
        reject(new Error(`gemini-companion ${subcommand} failed: ${detail}`));
        return;
      }

      // gemini-companion은 모든 서브커맨드가 plain text(stdout)를 뱉는다.
      // `result`가 숫자/문자열 등 JSON-valid 결과를 돌려줄 수 있으므로
      // JSON.parse 시도 없이 항상 raw로 보존한다.
      resolve({ raw: stdout });
    });
  });
}

function parseBackgroundJob(raw) {
  const startedMatch = raw.match(/\[gemini\]\s+Job started in background:\s+([^\s]+)/i);
  const statusMatch = raw.match(/\/gemini:status\s+([^\s]+)/i);
  const resultMatch = raw.match(/\/gemini:result\s+([^\s]+)/i);
  const jobId = startedMatch?.[1] ?? statusMatch?.[1] ?? resultMatch?.[1];

  if (!jobId) {
    throw new Error('Unable to extract jobId from gemini-companion task output');
  }

  return {
    jobId,
    mode: 'background',
    raw
  };
}

function parseStatusOutput(raw, requestedJobId) {
  if (raw.includes('[gemini] No jobs found.')) {
    return {
      mode: 'all',
      jobs: [],
      raw
    };
  }

  if (requestedJobId) {
    if (raw.includes('[gemini] Job not found:')) {
      return {
        jobId: requestedJobId,
        found: false,
        raw
      };
    }

    const result = {
      jobId: requestedJobId,
      found: true,
      raw
    };

    for (const line of raw.split(/\r?\n/)) {
      if (line.startsWith('Job: ')) {
        result.jobId = line.slice('Job: '.length).trim();
      } else if (line.startsWith('Status: ')) {
        result.status = line.slice('Status: '.length).trim();
      } else if (line.startsWith('Model: ')) {
        result.model = line.slice('Model: '.length).trim();
      } else if (line.startsWith('Started: ')) {
        result.startedAt = line.slice('Started: '.length).trim();
      } else if (line.startsWith('Completed: ')) {
        result.completedAt = line.slice('Completed: '.length).trim();
      }
    }
    return result;
  }

  const jobs = raw
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const match = /^(\S+)\s+(\S+)\s+(\S+)\s+(.*)$/.exec(line);
      if (!match) {
        return null;
      }
      return {
        jobId: match[1],
        status: match[2],
        startedAt: match[3],
        promptPreview: match[4]
      };
    })
    .filter(Boolean);

  return {
    mode: 'all',
    jobs,
    raw
  };
}

export function parseResultOutput(raw, jobId) {
  if (raw.includes('[gemini] Job not found:')) {
    return {
      jobId,
      found: false,
      raw
    };
  }
  if (raw.includes('[gemini] Result not available yet.')) {
    return {
      jobId,
      found: true,
      available: false,
      raw
    };
  }

  if (raw.trim().length === 0) {
    return {
      jobId,
      found: true,
      available: false,
      status: 'failed',
      error: 'empty output — likely terminal closure or upstream no-op',
      raw
    };
  }

  const trimmedOutput = raw.trim();
  const placeholderRemainder = trimmedOutput
    .replace(/health/gi, '')
    .replace(/check/gi, '')
    .replace(/ok/gi, '')
    .replace(/ping/gi, '')
    .replace(/[\W_]+/g, '');
  const isPlaceholder =
    /^Health Check OK/i.test(trimmedOutput) ||
    (trimmedOutput.length < 40 && /ok$|health|ping/i.test(trimmedOutput) && placeholderRemainder.length === 0);

  if (isPlaceholder) {
    return {
      jobId,
      found: true,
      available: false,
      status: 'failed',
      error: 'placeholder-output — likely upstream no-op',
      raw
    };
  }

  const errorSignatures = [
    /_GaxiosError/,
    /Attempt \d+ failed with status/,
    /"MODEL_CAPACITY_EXHAUSTED"/,
    /RESOURCE_EXHAUSTED/
  ];

  const earliestSignature = errorSignatures
    .map((pattern) => {
      const match = trimmedOutput.match(pattern);
      return match
        ? { index: match.index ?? -1, signature: match[0] }
        : null;
    })
    .filter((match) => match && match.index >= 0)
    .sort((left, right) => left.index - right.index)[0];

  if (earliestSignature) {
    const body = trimmedOutput.slice(0, earliestSignature.index).trim();

    if (earliestSignature.index === 0 || (earliestSignature.index <= 200 && body.length === 0)) {
      return {
        jobId,
        found: true,
        available: false,
        status: 'failed',
        error: 'upstream error before content',
        errorDump: trimmedOutput,
        raw
      };
    }

    const dump = trimmedOutput.slice(earliestSignature.index);
    return {
      jobId,
      found: true,
      available: true,
      output: body,
      warnings: [
        {
          type: 'trailing-error',
          signature: earliestSignature.signature,
          dump
        }
      ],
      raw
    };
  }

  return {
    jobId,
    found: true,
    available: true,
    output: trimmedOutput,
    raw
  };
}

function parseCancelOutput(raw, jobId) {
  if (raw.includes('[gemini] Job not found:')) {
    return {
      jobId,
      found: false,
      raw
    };
  }
  if (raw.includes('[gemini] No running job found.')) {
    return {
      jobId: jobId ?? null,
      cancelled: false,
      raw
    };
  }
  const cancelledMatch = raw.match(/\[gemini\]\s+Cancelled:\s+([^\s]+)/i);
  return {
    jobId: cancelledMatch?.[1] ?? jobId,
    cancelled: true,
    raw
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function geminiTask({ prompt, model, background = true }) {
  enforceDepthLimit('gemini_task');

  const args = [];

  if (background) {
    args.push('--background');
  }
  if (model) {
    args.push('--model', model);
  }
  args.push(prompt);

  const payload = await runCompanion('task', args, {
    timeoutMs: background ? DEFAULT_TIMEOUT_MS : FOREGROUND_TIMEOUT_MS
  });

  if (!background) {
    return {
      mode: 'foreground',
      output: payload.raw ?? '',
      raw: payload.raw ?? ''
    };
  }

  return parseBackgroundJob(payload.raw ?? '');
}

export async function geminiStatus({ jobId } = {}) {
  const args = [];
  if (jobId) {
    args.push(jobId);
  }
  const payload = await runCompanion('status', args);
  return parseStatusOutput(payload.raw ?? '', jobId);
}

export async function geminiResult({ jobId }) {
  const payload = await runCompanion('result', [jobId]);
  return parseResultOutput(payload.raw ?? '', jobId);
}

export async function geminiCancel({ jobId }) {
  const args = [];
  if (jobId) {
    args.push(jobId);
  }
  const payload = await runCompanion('cancel', args);
  return parseCancelOutput(payload.raw ?? '', jobId);
}

export async function geminiRun(input) {
  enforceDepthLimit('gemini_run');

  const {
    pollIntervalMs = 2000,
    timeoutMs = 600000,
    ...taskInput
  } = input;

  const startedAt = Date.now();
  const task = await geminiTask({ ...taskInput, background: true });
  const { jobId } = task;
  let polls = 0;

  while (Date.now() - startedAt < timeoutMs) {
    polls += 1;
    const statusPayload = await geminiStatus({ jobId });
    const status = typeof statusPayload?.status === 'string'
      ? statusPayload.status.toLowerCase()
      : undefined;

    if (status === 'completed') {
      const result = await geminiResult({ jobId });
      if (result?.status === 'failed') {
        return {
          jobId,
          status: 'failed',
          elapsedMs: Date.now() - startedAt,
          result,
          polls
        };
      }
      return {
        jobId,
        status: 'completed',
        elapsedMs: Date.now() - startedAt,
        result,
        polls
      };
    }

    if (status === 'failed' || status === 'cancelled') {
      const result = await geminiResult({ jobId });
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
