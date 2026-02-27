#!/usr/bin/env bash
# ============================================================
# orchestrate.sh — Dispatch tasks to worker agents
#
# Called by Claude Code (orchestrator) to delegate work.
# Handles: agent invocation, rate limit detection, fallback,
#          task brief generation, and result parsing.
#
# Usage:
#   bash orchestrate.sh codex "task description or @brief_file"
#   bash orchestrate.sh gemini "task description"
#   bash orchestrate.sh codex-spark "quick edit task"
#   bash orchestrate.sh gemini-pro "deep analysis task"
#   bash orchestrate.sh --brief "goal" "scope" "constraints"
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$REPO_DIR/logs"
TEMPLATE_DIR="$REPO_DIR/templates"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# --- Generate task brief from args ---
if [[ "${1:-}" == "--brief" ]]; then
  shift
  GOAL="${1:?Usage: orchestrate.sh --brief <goal> <scope> <constraints>}"
  SCOPE="${2:-unspecified}"
  CONSTRAINTS="${3:-none}"
  BRIEF_FILE="$LOG_DIR/brief_${TIMESTAMP}.md"
  cat > "$BRIEF_FILE" << BRIEF_EOF
## Goal
$GOAL

## Scope
- Files: $SCOPE

## Constraints
- $CONSTRAINTS

## Done Criteria
- [ ] Task completed successfully
- [ ] No errors in output
BRIEF_EOF
  echo "[BRIEF] Generated: $BRIEF_FILE"
  echo "$BRIEF_FILE"
  exit 0
fi

# --- Parse arguments ---
AGENT="${1:?Usage: orchestrate.sh <agent> <task> [task_name]}"
TASK="${2:?Usage: orchestrate.sh <agent> <task> [task_name]}"
TASK_NAME="${3:-unnamed}"
shift 2; shift 2>/dev/null || true

# --- Resolve task content ---
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

# --- Parse Codex JSON result → extract final message ---
parse_codex_result() {
  local raw="$1"
  # Extract the last agent_message text from JSONL
  local parsed
  parsed=$(echo "$raw" \
    | grep '"type":"agent_message"' \
    | tail -1 \
    | sed 's/.*"text":"\([^"]*\)".*/\1/' 2>/dev/null) || true

  if [ -n "$parsed" ]; then
    echo ""
    echo "--- Codex Summary ---"
    echo "$parsed"
  fi

  # Extract token usage
  local usage
  usage=$(echo "$raw" \
    | grep '"type":"turn.completed"' \
    | tail -1 \
    | grep -o '"usage":{[^}]*}' 2>/dev/null) || true

  if [ -n "$usage" ]; then
    echo ""
    echo "--- Token Usage ---"
    echo "$usage"
  fi
}

# --- Run Codex ---
run_codex() {
  local model="${1:-gpt-5.3-codex}"
  local log_file="$LOG_DIR/codex_${TASK_NAME}_${TIMESTAMP}.json"

  echo "[DISPATCH] Codex ($model) — task: $TASK_NAME"
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

  parse_codex_result "$result"
  return 0
}

# --- Run Gemini ---
run_gemini() {
  local model="${1:-gemini-2.5-flash}"
  local log_file="$LOG_DIR/gemini_${TASK_NAME}_${TIMESTAMP}.txt"

  echo "[DISPATCH] Gemini ($model) — task: $TASK_NAME"
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

  # Strip YOLO noise lines, show clean output
  echo ""
  echo "--- Gemini Result ---"
  echo "$result" | grep -v "YOLO mode\|Loaded cached\|^$"
  return 0
}

# --- Fallback logic ---
run_with_fallback_code() {
  echo "[INFO] Attempting code task with fallback chain..."

  if run_codex "gpt-5.3-codex"; then return 0; fi

  echo "[FALLBACK] Trying Gemini Flash..."
  if run_gemini "gemini-2.5-flash"; then return 0; fi

  echo "[QUEUED] All agents rate-limited. Task saved for retry."
  echo "$TASK" > "$LOG_DIR/queued_${TASK_NAME}_${TIMESTAMP}.md"
  return 1
}

run_with_fallback_research() {
  echo "[INFO] Attempting research task with fallback chain..."

  if run_gemini "gemini-2.5-flash"; then return 0; fi

  echo "[FALLBACK] Trying Codex..."
  if run_codex "gpt-5.3-codex"; then return 0; fi

  echo "[QUEUED] All agents rate-limited. Task saved for retry."
  echo "$TASK" > "$LOG_DIR/queued_${TASK_NAME}_${TIMESTAMP}.md"
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
    echo "Options:   --brief <goal> <scope> <constraints>"
    exit 1
    ;;
esac

echo ""
echo "[LOG] $LOG_DIR/${AGENT}_${TASK_NAME}_${TIMESTAMP}.*"
