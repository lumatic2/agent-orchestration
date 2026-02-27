#!/usr/bin/env bash
# ============================================================
# orchestrate.sh — Dispatch tasks to worker agents
#
# Called by Claude Code (orchestrator) to delegate work.
# Handles: agent invocation, rate limit detection, fallback,
#          task brief generation, result parsing, and persistent queue.
#
# Usage:
#   bash orchestrate.sh codex "task description or @brief_file" task-name
#   bash orchestrate.sh gemini "task description" task-name
#   bash orchestrate.sh codex-spark "quick edit task" task-name
#   bash orchestrate.sh gemini-pro "deep analysis task" task-name
#   bash orchestrate.sh --brief "goal" "scope" "constraints"
#   bash orchestrate.sh --boot           # scan queue on session start
#   bash orchestrate.sh --status         # show all queue entries
#   bash orchestrate.sh --resume         # re-dispatch oldest pending/queued
#   bash orchestrate.sh --complete T001 "summary"  # manually complete a task
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$REPO_DIR/logs"
QUEUE_DIR="$REPO_DIR/queue"
TEMPLATE_DIR="$REPO_DIR/templates"
ACTIVITY_LOG="$QUEUE_DIR/activity.jsonl"
mkdir -p "$LOG_DIR" "$QUEUE_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ISO_NOW=$(date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

# ============================================================
# Queue Helper Functions
# ============================================================

# Get next task ID (T001, T002, ...)
next_task_id() {
  local max=0
  for dir in "$QUEUE_DIR"/T[0-9][0-9][0-9]_*/; do
    [ -d "$dir" ] || continue
    local num="${dir##*/}"          # T001_name/
    num="${num%%_*}"                # T001
    num="${num#T}"                  # 001
    num=$((10#$num))               # 1
    [ "$num" -gt "$max" ] && max="$num"
  done
  printf "T%03d" $((max + 1))
}

# Create queue entry: create_queue_entry <id> <name> <agent> <task_content>
create_queue_entry() {
  local id="$1" name="$2" agent="$3" task_content="$4"
  local dir="$QUEUE_DIR/${id}_${name}"
  mkdir -p "$dir"

  cat > "$dir/meta.json" << META_EOF
{
  "id": "$id",
  "name": "$name",
  "status": "pending",
  "agent": "$agent",
  "model": "",
  "created": "$ISO_NOW",
  "dispatched": null,
  "completed": null,
  "exit_code": null,
  "log_file": null,
  "retry_count": 0,
  "queued_reason": null
}
META_EOF

  echo "$task_content" > "$dir/brief.md"
  log_activity "$id" "created" "agent=$agent"
}

# Update meta.json field: update_meta_status <task_dir> <status> [extra_field] [extra_value]
update_meta_status() {
  local dir="$1" new_status="$2"
  local extra_field="${3:-}" extra_value="${4:-}"
  local meta="$dir/meta.json"

  [ -f "$meta" ] || return 1

  # Update status
  sed -i "s/\"status\": *\"[^\"]*\"/\"status\": \"$new_status\"/" "$meta"

  # Update timestamp fields based on status
  case "$new_status" in
    dispatched)
      sed -i "s/\"dispatched\": *[^,]*/\"dispatched\": \"$ISO_NOW\"/" "$meta"
      ;;
    completed|failed)
      sed -i "s/\"completed\": *[^,]*/\"completed\": \"$ISO_NOW\"/" "$meta"
      ;;
    queued)
      # Increment retry_count
      local count
      count=$(grep -o '"retry_count": *[0-9]*' "$meta" | grep -o '[0-9]*')
      count=$((count + 1))
      sed -i "s/\"retry_count\": *[0-9]*/\"retry_count\": $count/" "$meta"
      if [ -n "$extra_value" ]; then
        sed -i "s/\"queued_reason\": *[^,}]*/\"queued_reason\": \"$extra_value\"/" "$meta"
      fi
      ;;
  esac

  # Set extra field if provided (e.g., exit_code, log_file)
  if [ -n "$extra_field" ] && [ "$new_status" != "queued" ]; then
    sed -i "s/\"$extra_field\": *[^,}]*/\"$extra_field\": \"$extra_value\"/" "$meta"
  fi

  local task_id
  task_id=$(basename "$dir" | cut -d_ -f1)
  log_activity "$task_id" "$new_status" ""
}

# Append to activity.jsonl
log_activity() {
  local id="$1" event="$2" detail="${3:-}"
  echo "{\"ts\":\"$ISO_NOW\",\"id\":\"$id\",\"event\":\"$event\",\"detail\":\"$detail\"}" >> "$ACTIVITY_LOG"
}

# Read status from meta.json
read_meta_field() {
  local meta="$1" field="$2"
  grep -o "\"$field\": *\"[^\"]*\"" "$meta" 2>/dev/null | sed 's/.*: *"\([^"]*\)"/\1/' || echo ""
}

read_meta_field_raw() {
  local meta="$1" field="$2"
  grep -o "\"$field\": *[^,}]*" "$meta" 2>/dev/null | sed 's/.*: *//' | tr -d '"' || echo ""
}

# ============================================================
# Subcommands: --boot, --status, --resume, --complete
# ============================================================

do_boot() {
  echo "=== Queue Boot Scan ==="
  local found=0

  # Check for stale dispatched (dispatched but no completion)
  for dir in "$QUEUE_DIR"/T[0-9][0-9][0-9]_*/; do
    [ -d "$dir" ] || continue
    local meta="$dir/meta.json"
    [ -f "$meta" ] || continue
    local status
    status=$(read_meta_field "$meta" "status")
    local name
    name=$(read_meta_field "$meta" "name")
    local id
    id=$(read_meta_field "$meta" "id")
    local agent
    agent=$(read_meta_field "$meta" "agent")

    case "$status" in
      dispatched)
        echo "[STALE] $id ($name) — dispatched to $agent but never completed"
        found=$((found + 1))
        ;;
      pending|queued)
        local reason
        reason=$(read_meta_field_raw "$meta" "queued_reason")
        echo "[PENDING] $id ($name) — agent: $agent ${reason:+(reason: $reason)}"
        found=$((found + 1))
        ;;
    esac
  done

  if [ "$found" -eq 0 ]; then
    echo "No pending or stale tasks. Queue is clean."
  else
    echo ""
    echo "$found task(s) need attention. Run --resume to re-dispatch oldest, or --status for details."
  fi
  exit 0
}

do_status() {
  echo "=== Queue Status ==="
  printf "%-6s %-25s %-12s %-12s %-8s\n" "ID" "NAME" "STATUS" "AGENT" "RETRIES"
  printf "%-6s %-25s %-12s %-12s %-8s\n" "------" "-------------------------" "------------" "------------" "--------"

  for dir in "$QUEUE_DIR"/T[0-9][0-9][0-9]_*/; do
    [ -d "$dir" ] || continue
    local meta="$dir/meta.json"
    [ -f "$meta" ] || continue

    local id name status agent retries
    id=$(read_meta_field "$meta" "id")
    name=$(read_meta_field "$meta" "name")
    status=$(read_meta_field "$meta" "status")
    agent=$(read_meta_field "$meta" "agent")
    retries=$(read_meta_field_raw "$meta" "retry_count")

    printf "%-6s %-25s %-12s %-12s %-8s\n" "$id" "$name" "$status" "$agent" "$retries"
  done
  exit 0
}

do_resume() {
  echo "=== Resuming oldest pending/queued task ==="

  for dir in "$QUEUE_DIR"/T[0-9][0-9][0-9]_*/; do
    [ -d "$dir" ] || continue
    local meta="$dir/meta.json"
    [ -f "$meta" ] || continue

    local status
    status=$(read_meta_field "$meta" "status")

    if [ "$status" = "pending" ] || [ "$status" = "queued" ] || [ "$status" = "dispatched" ]; then
      local id name agent brief_file
      id=$(read_meta_field "$meta" "id")
      name=$(read_meta_field "$meta" "name")
      agent=$(read_meta_field "$meta" "agent")
      brief_file="$dir/brief.md"

      if [ ! -f "$brief_file" ]; then
        echo "[ERROR] No brief.md found for $id"
        exit 1
      fi

      echo "[RESUME] Re-dispatching $id ($name) to $agent"

      # Re-run with the original agent and brief
      TASK=$(cat "$brief_file")
      TASK_NAME="$name"
      QUEUE_TASK_DIR="$dir"

      update_meta_status "$dir" "dispatched"

      case "$agent" in
        codex)       run_codex "gpt-5.3-codex" ;;
        codex-spark) run_codex "gpt-5.3-codex-spark" ;;
        gemini)      run_gemini "gemini-2.5-flash" ;;
        gemini-pro)  run_gemini "gemini-2.5-pro" ;;
        *)
          echo "[ERROR] Unknown agent in queue: $agent"
          exit 1
          ;;
      esac

      local exit_code=$?
      if [ "$exit_code" -eq 0 ]; then
        update_meta_status "$dir" "completed"
        echo "[DONE] $id completed."
      else
        update_meta_status "$dir" "queued" "queued_reason" "rate_limited"
        echo "[QUEUED] $id re-queued (rate limited)."
      fi
      exit 0
    fi
  done

  echo "No pending/queued/stale tasks to resume."
  exit 0
}

do_complete() {
  local target_id="${1:?Usage: orchestrate.sh --complete <TASK_ID> \"summary\"}"
  local summary="${2:-Manually completed}"

  for dir in "$QUEUE_DIR"/T[0-9][0-9][0-9]_*/; do
    [ -d "$dir" ] || continue
    local meta="$dir/meta.json"
    [ -f "$meta" ] || continue
    local id
    id=$(read_meta_field "$meta" "id")

    if [ "$id" = "$target_id" ]; then
      update_meta_status "$dir" "completed"
      echo "$summary" > "$dir/result.md"
      echo "[COMPLETE] $target_id marked as completed."
      exit 0
    fi
  done

  echo "[ERROR] Task $target_id not found in queue."
  exit 1
}

# ============================================================
# Handle subcommands before main dispatch
# ============================================================

case "${1:-}" in
  --boot)     do_boot ;;
  --status)   do_status ;;
  --resume)   do_resume ;;
  --complete) shift; do_complete "$@" ;;
esac

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

# --- Create queue entry for this dispatch ---
QUEUE_TASK_ID=$(next_task_id)
create_queue_entry "$QUEUE_TASK_ID" "$TASK_NAME" "$AGENT" "$TASK"
QUEUE_TASK_DIR="$QUEUE_DIR/${QUEUE_TASK_ID}_${TASK_NAME}"
echo "[QUEUE] Created $QUEUE_TASK_ID ($TASK_NAME)"

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

  # Update queue status to dispatched
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "dispatched"
  [ -d "${QUEUE_TASK_DIR:-}" ] && sed -i "s/\"model\": *\"[^\"]*\"/\"model\": \"$model\"/" "$QUEUE_TASK_DIR/meta.json"

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
    [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "queued" "queued_reason" "rate_limited"
    [ -d "${QUEUE_TASK_DIR:-}" ] && sed -i "s|\"log_file\": *[^,]*|\"log_file\": \"$log_file\"|" "$QUEUE_TASK_DIR/meta.json"
    return 1
  fi

  # Success — update queue
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "completed"
  [ -d "${QUEUE_TASK_DIR:-}" ] && sed -i "s|\"log_file\": *[^,]*|\"log_file\": \"$log_file\"|" "$QUEUE_TASK_DIR/meta.json"
  [ -d "${QUEUE_TASK_DIR:-}" ] && echo "$result" > "$QUEUE_TASK_DIR/result.md"

  parse_codex_result "$result"
  return 0
}

# --- Run Gemini ---
run_gemini() {
  local model="${1:-gemini-2.5-flash}"
  local log_file="$LOG_DIR/gemini_${TASK_NAME}_${TIMESTAMP}.txt"

  echo "[DISPATCH] Gemini ($model) — task: $TASK_NAME"

  # Update queue status to dispatched
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "dispatched"
  [ -d "${QUEUE_TASK_DIR:-}" ] && sed -i "s/\"model\": *\"[^\"]*\"/\"model\": \"$model\"/" "$QUEUE_TASK_DIR/meta.json"

  local result
  result=$(gemini \
    --yolo \
    -m "$model" \
    -p "$TASK" 2>&1) || true

  echo "$result" > "$log_file"

  if is_rate_limited "$result"; then
    echo "[RATE_LIMIT] Gemini hit rate limit"
    [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "queued" "queued_reason" "rate_limited"
    [ -d "${QUEUE_TASK_DIR:-}" ] && sed -i "s|\"log_file\": *[^,]*|\"log_file\": \"$log_file\"|" "$QUEUE_TASK_DIR/meta.json"
    return 1
  fi

  # Success — update queue
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "completed"
  [ -d "${QUEUE_TASK_DIR:-}" ] && sed -i "s|\"log_file\": *[^,]*|\"log_file\": \"$log_file\"|" "$QUEUE_TASK_DIR/meta.json"
  [ -d "${QUEUE_TASK_DIR:-}" ] && echo "$result" > "$QUEUE_TASK_DIR/result.md"

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

  echo "[QUEUED] All agents rate-limited. Task queued for retry."
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "queued" "queued_reason" "all_agents_rate_limited"
  return 1
}

run_with_fallback_research() {
  echo "[INFO] Attempting research task with fallback chain..."

  if run_gemini "gemini-2.5-flash"; then return 0; fi

  echo "[FALLBACK] Trying Codex..."
  if run_codex "gpt-5.3-codex"; then return 0; fi

  echo "[QUEUED] All agents rate-limited. Task queued for retry."
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "queued" "queued_reason" "all_agents_rate_limited"
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
    echo "Options:   --boot, --status, --resume, --complete <ID> <summary>"
    echo "           --brief <goal> <scope> <constraints>"
    exit 1
    ;;
esac

echo ""
echo "[LOG] $LOG_DIR/${AGENT}_${TASK_NAME}_${TIMESTAMP}.*"
echo "[QUEUE] $QUEUE_TASK_DIR/"
