#!/usr/bin/env node
// job-watcher.mjs — background watcher for codex/gemini companion jobs
// Phase 1: codex-companion only. Detects terminal-state jobs via state.json polling.
// Usage:
//   node job-watcher.mjs --detach   # spawn background worker, write pid file, exit
//   node job-watcher.mjs --run      # foreground polling loop (called by --detach)

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import https from "node:https";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const SELF = fileURLToPath(import.meta.url);
const HOOK_DIR = path.join(os.homedir(), ".claude", "hooks");
const PID_FILE = path.join(HOOK_DIR, ".job-watcher.pid");
const LOG_FILE = path.join(HOOK_DIR, "job-watcher.log");
const CODEX_ROOT = path.join(os.tmpdir(), "codex-companion");
const GEMINI_JOBS_DIR = path.join(
  os.homedir(),
  ".claude", "plugins", "cache", "claude-gemini-plugin", "gemini", "1.0.0", "jobs",
);
const TELEGRAM_SCRIPT = path.join(os.homedir(), ".claude", "telegram-notify.sh");
const POLL_MS = 1500;
const TERMINAL = new Set(["completed", "failed", "cancelled", "error"]);

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}\n`;
  try { fs.appendFileSync(LOG_FILE, line); } catch { /* ignore */ }
}

function isAlive(pid) {
  if (!pid || Number.isNaN(pid)) return false;
  try { process.kill(pid, 0); return true; } catch { return false; }
}

function cmdDetach() {
  if (fs.existsSync(PID_FILE)) {
    const pid = parseInt(fs.readFileSync(PID_FILE, "utf8").trim(), 10);
    if (isAlive(pid)) {
      console.log(`[job-watcher] already running (pid ${pid})`);
      return;
    }
  }
  const child = spawn(process.execPath, [SELF, "--run"], {
    detached: true,
    stdio: "ignore",
    windowsHide: true,
  });
  child.unref();
  fs.writeFileSync(PID_FILE, String(child.pid));
  log(`detach spawned pid=${child.pid}`);
  console.log(`[job-watcher] started (pid ${child.pid})`);
}

function fmtDuration(startIso, endIso) {
  if (!startIso || !endIso) return "";
  const s = Math.round((new Date(endIso) - new Date(startIso)) / 1000);
  if (!Number.isFinite(s) || s < 0) return "";
  return s >= 60 ? `${Math.floor(s / 60)}m ${s % 60}s` : `${s}s`;
}

let telegramCreds = null;
function loadTelegramCreds() {
  if (telegramCreds !== null) return telegramCreds;
  try {
    const src = fs.readFileSync(TELEGRAM_SCRIPT, "utf8");
    const token = src.match(/TG_BOT_TOKEN="([^"]+)"/)?.[1];
    const chatId = src.match(/TG_CHAT_ID="([^"]+)"/)?.[1];
    if (token && chatId) {
      telegramCreds = { token, chatId };
      return telegramCreds;
    }
  } catch (err) {
    log(`telegram: cred load failed ${err.message}`);
  }
  telegramCreds = false;
  return false;
}

function sendTelegram(text) {
  const creds = loadTelegramCreds();
  if (!creds) { log("telegram: creds unavailable, skipping"); return; }
  const body = new URLSearchParams({ chat_id: creds.chatId, text }).toString();
  const req = https.request({
    method: "POST",
    hostname: "api.telegram.org",
    path: `/bot${creds.token}/sendMessage`,
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "Content-Length": Buffer.byteLength(body),
    },
    timeout: 5000,
  }, (res) => {
    if (res.statusCode !== 200) log(`telegram: HTTP ${res.statusCode}`);
    res.resume();
  });
  req.on("error", (err) => log(`telegram: request error ${err.message}`));
  req.on("timeout", () => { log("telegram: timeout"); req.destroy(); });
  req.write(body);
  req.end();
}

function notify(kind, job) {
  const ok = job.status === "completed" && (job.exitCode == null || job.exitCode === 0);
  const icon = ok ? "✅" : "❌";
  const dur = fmtDuration(job.startedAt, job.completedAt || job.cancelledAt);
  const title = job.title || job.kindLabel || job.model || kind;
  const msg = `${icon} ${kind} ${job.id} ${job.status}${dur ? ` (${dur})` : ""} — ${title}`;
  log(`notify ${msg}`);
  try { process.stdout.write("\x07"); } catch { /* ignore */ }
  const tgText = [
    `${icon} ${kind[0].toUpperCase() + kind.slice(1)} ${job.status}`,
    job.id,
    dur ? `duration: ${dur}` : null,
    ok ? `→ /${kind}:result ${job.id}` : `→ /${kind}:result ${job.id}`,
  ].filter(Boolean).join("\n");
  sendTelegram(tgText);
}

function scanCodex(prime, seen) {
  let entries;
  try { entries = fs.readdirSync(CODEX_ROOT, { withFileTypes: true }); }
  catch { return; }
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    const statePath = path.join(CODEX_ROOT, e.name, "state.json");
    let state;
    try { state = JSON.parse(fs.readFileSync(statePath, "utf8")); }
    catch { continue; }
    for (const job of state.jobs || []) {
      if (!job.id || !TERMINAL.has(job.status)) continue;
      const key = `codex:${job.id}`;
      if (seen.has(key)) continue;
      seen.add(key);
      if (prime) continue;
      notify("codex", job);
    }
  }
}

function scanGemini(prime, seen) {
  let entries;
  try { entries = fs.readdirSync(GEMINI_JOBS_DIR); }
  catch { return; }
  for (const name of entries) {
    if (!name.endsWith(".json")) continue;
    const jsonPath = path.join(GEMINI_JOBS_DIR, name);
    let job;
    try { job = JSON.parse(fs.readFileSync(jsonPath, "utf8")); }
    catch { continue; }
    if (!job.id) continue;
    // Terminal if status is non-running OR the .done sentinel exists.
    const doneExists = job.doneFile && fs.existsSync(job.doneFile);
    const terminal = (job.status && job.status !== "running") || doneExists;
    if (!terminal) continue;
    const key = `gemini:${job.id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    if (prime) continue;
    // Normalize status for notify if derived from .done sentinel.
    if (doneExists && job.status === "running") job.status = "completed";
    notify("gemini", job);
  }
}

function scanAll(prime, seen) {
  scanCodex(prime, seen);
  scanGemini(prime, seen);
}

function cmdRun() {
  fs.writeFileSync(PID_FILE, String(process.pid));
  log(`run start pid=${process.pid}`);
  const seen = new Set();
  scanAll(true, seen);
  log(`primed seen=${seen.size}`);
  setInterval(() => scanAll(false, seen), POLL_MS);
  process.on("SIGTERM", () => { log("SIGTERM"); process.exit(0); });
  process.on("SIGINT", () => { log("SIGINT"); process.exit(0); });
}

const mode = process.argv[2];
if (mode === "--detach") cmdDetach();
else if (mode === "--run") cmdRun();
else {
  console.error("usage: job-watcher.mjs --detach | --run");
  process.exit(1);
}
