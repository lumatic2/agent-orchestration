#!/usr/bin/env bash
# ============================================================
# orchestrate.sh — Dispatch tasks to worker agents
#
# Called by Claude Code (orchestrator) to delegate work.
# Handles: agent invocation, rate limit detection, fallback.
#
# Usage:
#   bash orchestrate.sh codex "task description or @brief_file"
#   bash orchestrate.sh gemini "task description or @brief_file"
#   bash orchestrate.sh codex-spark "quick edit task"
#   bash orchestrate.sh gemini-pro "deep analysis task"
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# --- Parse arguments ---
AGENT="${1:?Usage: orchestrate.sh <agent> <task>}"
TASK="${2:?Usage: orchestrate.sh <agent> <task>}"
shift 2

# --- Resolve task content ---
# If task starts with @, read from file
if [[ "$TASK" == @* ]]; then
  TASK_FILE="${TASK#@}"
  if [ -f "$TASK_FILE" ]; then
    TASK=$(cat "$TASK_FILE")
  else
    echo "[ERROR] Task file not found: $TASK_FILE"
    exit 1
  fi
fi

# --- Rate limit detection ---
is_rate_limited() {
  local output="$1"
  if echo "$output" | grep -qEi "rate.?limit|429|quota|exceeded|too.?many.?requests|resource.?exhausted"; then
    return 0
  fi
  return 1
}

# --- Run Codex ---
run_codex() {
  local model="${1:-gpt-5.3-codex}"
  local log_file="$LOG_DIR/codex_${TIMESTAMP}.json"

  echo "[DISPATCH] Codex ($model)"
  local result
  result=$(codex exec \
    --full-auto \
    --sandbox danger-full-access \
    -m "$model" \
    "$TASK" \
    --json 2>&1) || true

  echo "$result" > "$log_file"

  if is_rate_limited "$result"; then
    echo "[RATE_LIMIT] Codex hit rate limit"
    return 1
  fi

  echo "$result"
  return 0
}

# --- Run Gemini ---
run_gemini() {
  local model="${1:-gemini-2.5-flash}"
  local log_file="$LOG_DIR/gemini_${TIMESTAMP}.txt"

  echo "[DISPATCH] Gemini ($model)"
  local result
  result=$(gemini \
    --yolo \
    -m "$model" \
    -p "$TASK" 2>&1) || true

  echo "$result" > "$log_file"

  if is_rate_limited "$result"; then
    echo "[RATE_LIMIT] Gemini hit rate limit"
    return 1
  fi

  echo "$result"
  return 0
}

# --- Fallback logic ---
run_with_fallback_code() {
  echo "[INFO] Attempting code task with fallback chain..."

  # 1st: Codex
  if run_codex "gpt-5.3-codex"; then
    return 0
  fi

  # 2nd: Gemini (fallback)
  echo "[FALLBACK] Trying Gemini Flash..."
  if run_gemini "gemini-2.5-flash"; then
    return 0
  fi

  # 3rd: Queue
  echo "[QUEUED] All agents rate-limited. Task saved for retry."
  echo "$TASK" > "$LOG_DIR/queued_${TIMESTAMP}.md"
  return 1
}

run_with_fallback_research() {
  echo "[INFO] Attempting research task with fallback chain..."

  # 1st: Gemini Flash
  if run_gemini "gemini-2.5-flash"; then
    return 0
  fi

  # 2nd: Codex (fallback for research)
  echo "[FALLBACK] Trying Codex..."
  if run_codex "gpt-5.3-codex"; then
    return 0
  fi

  # 3rd: Queue
  echo "[QUEUED] All agents rate-limited. Task saved for retry."
  echo "$TASK" > "$LOG_DIR/queued_${TIMESTAMP}.md"
  return 1
}

# --- Main dispatch ---
case "$AGENT" in
  codex)
    run_codex "gpt-5.3-codex" || run_with_fallback_code
    ;;
  codex-spark)
    run_codex "gpt-5.3-codex-spark" || run_with_fallback_code
    ;;
  gemini)
    run_gemini "gemini-2.5-flash" || run_with_fallback_research
    ;;
  gemini-pro)
    run_gemini "gemini-2.5-pro" || run_with_fallback_research
    ;;
  codex-fallback)
    run_with_fallback_code
    ;;
  gemini-fallback)
    run_with_fallback_research
    ;;
  *)
    echo "[ERROR] Unknown agent: $AGENT"
    echo "Available: codex, codex-spark, gemini, gemini-pro, codex-fallback, gemini-fallback"
    exit 1
    ;;
esac

echo ""
echo "[LOG] Results saved to $LOG_DIR/"
