#!/usr/bin/env bash
# ============================================================
# guard.sh — Safety hook for --dangerously-skip-permissions
# Blocks destructive commands even in auto-approve mode.
#
# Usage: Called by Claude Code hooks (PreToolUse for Bash).
#   .claude/settings.json → hooks.PreToolUse[].command
# ============================================================

INPUT="$1"

# --- Destructive file operations ---
if echo "$INPUT" | grep -qEi "rm\s+-rf\s+[/~]|rm\s+-rf\s+\.\s*$|rmdir\s+/"; then
  echo "BLOCKED: Destructive delete targeting root or home directory" >&2
  exit 1
fi

# --- Dangerous git operations ---
if echo "$INPUT" | grep -qEi "git\s+push\s+--force|git\s+push\s+-f\s|git\s+reset\s+--hard|git\s+clean\s+-fd"; then
  echo "BLOCKED: Destructive git operation. Use non-destructive alternatives." >&2
  exit 1
fi

# --- Sensitive file access ---
if echo "$INPUT" | grep -qEi "\.env|credentials|\.secret|private.key|id_rsa"; then
  echo "BLOCKED: Sensitive file access detected. Requires manual approval." >&2
  exit 1
fi

# --- Dangerous SQL ---
if echo "$INPUT" | grep -qEi "DROP\s+TABLE|DROP\s+DATABASE|DELETE\s+FROM\s+\w+\s*$|TRUNCATE\s+TABLE"; then
  echo "BLOCKED: Destructive SQL operation without WHERE clause." >&2
  exit 1
fi

# --- System-wide package operations ---
if echo "$INPUT" | grep -qEi "npm\s+install\s+-g|pip\s+install\s+--system|sudo\s+apt\s+remove"; then
  echo "BLOCKED: System-wide package operation. Use local/venv installs." >&2
  exit 1
fi

# Passed all checks
exit 0
