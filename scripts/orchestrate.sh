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
#   bash orchestrate.sh --cost           # today's usage per model + limits
#   bash orchestrate.sh --clean [--dry]  # archive completed queue entries
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
# Dynamic timestamp — call now_iso() each time to avoid all timestamps being identical
now_iso() { date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || date +%Y-%m-%dT%H:%M:%S; }

# Cross-platform sed -i wrapper (macOS BSD sed requires -i '')
sedi() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# ============================================================
# Queue Helper Functions
# ============================================================

# Get next task ID (T001, T002, ...)
next_task_id() {
  local max=0
  for dir in "$QUEUE_DIR"/T[0-9][0-9][0-9]_*/; do
    [ -d "$dir" ] || continue
    local dirname
    dirname="$(basename "$dir")"   # T001_name
    local tag="${dirname%%_*}"     # T001
    local digits="${tag#T}"        # 001
    # Strip leading zeros safely
    digits="${digits#0}"; digits="${digits#0}"
    local num="${digits:-0}"
    [ "$num" -gt "$max" ] && max="$num"
  done
  printf "T%03d" $((max + 1))
}

# Create queue entry: create_queue_entry <id> <name> <agent> <task_content>
create_queue_entry() {
  local id="$1" name="$2" agent="$3" task_content="$4"
  local ISO_NOW; ISO_NOW=$(now_iso)
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
  sedi "s/\"status\": *\"[^\"]*\"/\"status\": \"$new_status\"/" "$meta"

  # Update timestamp fields based on status
  case "$new_status" in
    dispatched)
      sedi "s/\"dispatched\": *[^,]*/\"dispatched\": \"$(now_iso)\"/" "$meta"
      ;;
    completed|failed)
      sedi "s/\"completed\": *[^,]*/\"completed\": \"$(now_iso)\"/" "$meta"
      ;;
    queued)
      # Increment retry_count
      local count
      count=$(grep -o '"retry_count": *[0-9]*' "$meta" | grep -o '[0-9]*')
      count=$((count + 1))
      sedi "s/\"retry_count\": *[0-9]*/\"retry_count\": $count/" "$meta"
      if [ -n "$extra_value" ]; then
        sedi "s/\"queued_reason\": *[^,}]*/\"queued_reason\": \"$extra_value\"/" "$meta"
      fi
      ;;
  esac

  # Set extra field if provided (e.g., exit_code, log_file)
  if [ -n "$extra_field" ] && [ "$new_status" != "queued" ]; then
    sedi "s/\"$extra_field\": *[^,}]*/\"$extra_field\": \"$extra_value\"/" "$meta"
  fi

  local task_id
  task_id=$(basename "$dir" | cut -d_ -f1)
  log_activity "$task_id" "$new_status" ""
}

# Append to activity.jsonl
log_activity() {
  local id="$1" event="$2" detail="${3:-}"
  echo "{\"ts\":\"$(now_iso)\",\"id\":\"$id\",\"event\":\"$event\",\"detail\":\"$detail\"}" >> "$ACTIVITY_LOG"
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
# Agent Functions (defined before subcommands so --resume can use them)
# ============================================================

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

# --- Inter-dispatch rate guard (per agent) ---
# Ensures minimum 3s gap between consecutive dispatches to same agent family
dispatch_guard() {
  local agent_family="$1"  # "codex" or "gemini"
  local min_gap=3
  local stamp_file="$QUEUE_DIR/.last_dispatch_${agent_family}"
  if [ -f "$stamp_file" ]; then
    local last_ts now_ts elapsed
    last_ts=$(cat "$stamp_file")
    now_ts=$(date +%s)
    elapsed=$((now_ts - last_ts))
    if [ "$elapsed" -lt "$min_gap" ]; then
      local wait_sec=$((min_gap - elapsed))
      echo "[GUARD] Waiting ${wait_sec}s before next ${agent_family} dispatch (rate limit prevention)"
      sleep "$wait_sec"
    fi
  fi
  date +%s > "$stamp_file"
}

# --- Run Codex ---
run_codex() {
  local model="${1:-gpt-5.3-codex}"
  local log_file="$LOG_DIR/codex_${TASK_NAME}_${TIMESTAMP}.json"

  dispatch_guard "codex"
  echo "[DISPATCH] Codex ($model) — task: $TASK_NAME"

  # Update queue status to dispatched
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "dispatched"
  [ -d "${QUEUE_TASK_DIR:-}" ] && sedi "s/\"model\": *\"[^\"]*\"/\"model\": \"$model\"/" "$QUEUE_TASK_DIR/meta.json"

  # Detect project working directory from brief (line: "프로젝트 위치" or "Project:" or "## Directory")
  local work_dir=""
  if [ -n "${QUEUE_TASK_DIR:-}" ] && [ -f "${QUEUE_TASK_DIR}/brief.md" ]; then
    local detected
    detected=$(grep -Eo '(C:/|/c/)[^\s]+' "${QUEUE_TASK_DIR}/brief.md" | head -1 | tr -d '\r')
    if [ -n "$detected" ] && [ -d "$detected" ]; then
      work_dir="$detected"
      echo "[INFO] Codex working dir: $work_dir"
    fi
  fi

  # Build codex command args
  local codex_args=(
    exec
    --dangerously-bypass-approvals-and-sandbox
    --skip-git-repo-check
    -m "$model"
    --json
  )
  [ -n "$work_dir" ] && codex_args+=(-C "$work_dir")

  # Write directly to file to avoid shell variable truncation
  codex "${codex_args[@]}" "$TASK" > "$log_file" 2>&1 || true

  local result
  result=$(cat "$log_file")

  if is_rate_limited "$result"; then
    echo "[RATE_LIMIT] Codex hit rate limit"
    [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "queued" "queued_reason" "rate_limited"
    [ -d "${QUEUE_TASK_DIR:-}" ] && sedi "s|\"log_file\": *[^,]*|\"log_file\": \"$log_file\"|" "$QUEUE_TASK_DIR/meta.json"
    return 1
  fi

  # Success — update queue
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "completed"
  [ -d "${QUEUE_TASK_DIR:-}" ] && sedi "s|\"log_file\": *[^,]*|\"log_file\": \"$log_file\"|" "$QUEUE_TASK_DIR/meta.json"
  [ -d "${QUEUE_TASK_DIR:-}" ] && echo "$result" > "$QUEUE_TASK_DIR/result.md"

  parse_codex_result "$result"
  return 0
}

# --- Run Gemini ---
run_gemini() {
  local model="${1:-gemini-2.5-flash}"
  local log_file="$LOG_DIR/gemini_${TASK_NAME}_${TIMESTAMP}.txt"

  dispatch_guard "gemini"
  echo "[DISPATCH] Gemini ($model) — task: $TASK_NAME"

  # Update queue status to dispatched
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "dispatched"
  [ -d "${QUEUE_TASK_DIR:-}" ] && sedi "s/\"model\": *\"[^\"]*\"/\"model\": \"$model\"/" "$QUEUE_TASK_DIR/meta.json"

  # Write directly to file to avoid shell variable truncation
  gemini \
    --yolo \
    -m "$model" \
    -p "$TASK" > "$log_file" 2>&1 || true

  local result
  result=$(cat "$log_file")

  if is_rate_limited "$result"; then
    echo "[RATE_LIMIT] Gemini hit rate limit"
    [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "queued" "queued_reason" "rate_limited"
    [ -d "${QUEUE_TASK_DIR:-}" ] && sedi "s|\"log_file\": *[^,]*|\"log_file\": \"$log_file\"|" "$QUEUE_TASK_DIR/meta.json"
    return 1
  fi

  # Success — update queue
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "completed"
  [ -d "${QUEUE_TASK_DIR:-}" ] && sedi "s|\"log_file\": *[^,]*|\"log_file\": \"$log_file\"|" "$QUEUE_TASK_DIR/meta.json"
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

# ============================================================
# Subcommands: --boot, --status, --resume, --complete, --cost, --clean
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

      local exit_code=0
      case "$agent" in
        codex)         run_codex "gpt-5.3-codex" || exit_code=$? ;;
        codex-spark)   run_codex "gpt-5.3-codex-spark" || exit_code=$? ;;
        chatgpt)       run_codex "gpt-5.2" || exit_code=$? ;;
        chatgpt-mini)  run_codex "gpt-5.1" || exit_code=$? ;;
        chatgpt-light) run_codex "gpt-5" || exit_code=$? ;;
        gemini)        run_gemini "gemini-2.5-flash" || exit_code=$? ;;
        gemini-pro)    run_gemini "gemini-2.5-pro" || exit_code=$? ;;
        *)
          echo "[ERROR] Unknown agent in queue: $agent"
          exit 1
          ;;
      esac
      # run_codex/run_gemini already record completed internally — only handle failure here
      if [ "$exit_code" -eq 0 ]; then
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

do_cost() {
  local period="${1:-today}"   # today | week | all
  python3 - "$QUEUE_DIR" "$REPO_DIR/archive/queue" "$period" << 'PYEOF'
import json, sys
from pathlib import Path
from datetime import date, timedelta

queue_dir   = Path(sys.argv[1])
archive_dir = Path(sys.argv[2])
period      = sys.argv[3] if len(sys.argv) > 3 else "today"

today = date.today()
if period == "week":
    cutoff = str(today - timedelta(days=7))
    period_label = f"최근 7일 ({cutoff} ~ {today})"
elif period == "all":
    cutoff = "2000-01-01"
    period_label = "전체 기간"
else:
    cutoff = str(today)
    period_label = f"오늘 ({today})"

LIMITS = {
    "gemini-2.5-pro": 100,
    "gemini-2.5-flash": 300,
    "gemini-2.5-flash-lite": 500,
}

# 에이전트 유형 분류 (task name 기반)
AGENT_KEYWORDS = {
    "tax": ["tax", "세무", "법인세", "부가세", "소득세"],
    "expert": ["expert", "audit", "valuation", "deal", "ifrs", "forensic", "wealth", "law"],
    "content": ["content", "콘텐츠", "pipeline"],
    "codex": ["codex", "code", "코드"],
    "gemini": ["gemini", "research", "분석"],
}

def classify_agent(task_name, agent):
    name_lower = (task_name or "").lower()
    if agent in ("codex", "codex-spark"):
        return "codex"
    if agent in ("gemini", "gemini-pro"):
        for kw in AGENT_KEYWORDS.get("tax", []):
            if kw in name_lower:
                return "tax"
        for kw in AGENT_KEYWORDS.get("expert", []):
            if kw in name_lower:
                return "expert"
        for kw in AGENT_KEYWORDS.get("content", []):
            if kw in name_lower:
                return "content"
        return "gemini"
    return agent or "unknown"

model_counts  = {}   # 모델별 사용 횟수
agent_counts  = {}   # 에이전트 유형별 사용 횟수
total = completed_cnt = pending_cnt = 0

# 활성 큐 + 아카이브 모두 스캔
all_dirs = []
if queue_dir.exists():
    all_dirs += list(queue_dir.glob("T[0-9][0-9][0-9]_*/"))
if archive_dir.exists():
    all_dirs += list(archive_dir.glob("T[0-9][0-9][0-9]_*/"))

for d_path in sorted(all_dirs):
    meta_path = d_path / "meta.json"
    if not meta_path.exists():
        continue
    try:
        d = json.loads(meta_path.read_text())
    except Exception:
        continue

    total += 1
    status = d.get("status", "")
    if status == "completed":
        completed_cnt += 1
    elif status in ("pending", "queued"):
        pending_cnt += 1

    completed_ts = d.get("completed") or ""
    # completed_ts 형식: "2026-03-05T14:23:01" or "2026-03-05 14:23:01"
    ts_date = completed_ts[:10]
    if ts_date < cutoff:
        continue
    if status != "completed":
        continue

    model = d.get("model") or d.get("agent") or "unknown"
    task_name = d.get("name") or ""
    agent = d.get("agent") or ""

    model_counts[model] = model_counts.get(model, 0) + 1
    atype = classify_agent(task_name, agent)
    agent_counts[atype] = agent_counts.get(atype, 0) + 1

# ─── 출력 ────────────────────────────────────────────────────
print(f"\n=== Agent Usage ({period_label}) ===\n")

if not model_counts:
    print("  (해당 기간 완료된 작업 없음)")
else:
    # 모델별
    print(f"  [모델별]")
    print(f"  {'모델':<30} {'호출':>5} {'한도':>5}  {'bar'}")
    print(f"  {'-'*30} {'-----':>5} {'-----':>5}")
    for model, count in sorted(model_counts.items(), key=lambda x: -x[1]):
        limit = LIMITS.get(model)
        limit_str = str(limit) if limit else "∞"
        warn = ""
        bar = ""
        if limit:
            pct = count / limit
            bar_len = min(int(pct * 20), 20)
            bar = "█" * bar_len + "░" * (20 - bar_len) + f" {pct*100:.0f}%"
            if pct >= 0.8:
                warn = " ⚠️"
        print(f"  {model:<30} {count:>5} {limit_str:>5}{warn}  {bar}")

    # 에이전트 유형별
    print(f"\n  [에이전트 유형별]")
    total_calls = sum(agent_counts.values())
    for atype, count in sorted(agent_counts.items(), key=lambda x: -x[1]):
        pct = count / total_calls * 100 if total_calls else 0
        bar_len = min(int(pct / 5), 20)
        bar = "█" * bar_len
        print(f"  {atype:<20} {count:>4}회  {bar} {pct:.0f}%")

print(f"\n  큐 전체: {total}개 (완료 {completed_cnt} / 대기 {pending_cnt})")
print("  정리: bash orchestrate.sh --clean")
print("  주간: bash orchestrate.sh --cost week")
print("  전체: bash orchestrate.sh --cost all")
PYEOF
  exit 0
}

do_clean() {
  # 완료된 큐 항목을 archive/queue/로 이동
  local dry="${1:-}"
  local archive_dir="$REPO_DIR/archive/queue"
  mkdir -p "$archive_dir"

  local moved=0 skipped=0

  echo "=== Queue Clean ==="
  [ "$dry" = "--dry" ] && echo "(DRY RUN — 실제 변경 없음)"
  echo ""

  for dir in "$QUEUE_DIR"/T[0-9][0-9][0-9]_*/; do
    [ -d "$dir" ] || continue
    local meta="$dir/meta.json"
    [ -f "$meta" ] || continue

    local status id name
    status=$(read_meta_field "$meta" "status")
    id=$(read_meta_field "$meta" "id")
    name=$(read_meta_field "$meta" "name")

    if [ "$status" = "completed" ]; then
      echo "  [ARCHIVE] $id ($name)"
      if [ "$dry" != "--dry" ]; then
        mv "$dir" "$archive_dir/"
      fi
      moved=$((moved + 1))
    else
      skipped=$((skipped + 1))
    fi
  done

  echo ""
  if [ "$dry" = "--dry" ]; then
    echo "DRY RUN 완료: ${moved}개 아카이브 예정, ${skipped}개 유지"
  else
    echo "완료: ${moved}개 → $archive_dir"
    echo "     ${skipped}개 유지 (미완료)"
    [ "$moved" -gt 0 ] && log_activity "CLEAN" "archived" "count=$moved"
  fi
  exit 0
}

# ============================================================
# Handle subcommands before main dispatch
# ============================================================

case "${1:-}" in
  --boot)     do_boot ;;
  --status)   do_status ;;
  --resume)   do_resume ;;
  --complete) shift; do_complete "$@" ;;
  --cost)     do_cost ;;
  --clean)    shift; do_clean "${1:-}" ;;
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
  chatgpt)
    run_codex "gpt-5.2" || run_with_fallback_research
    ;;
  chatgpt-mini)
    run_codex "gpt-5.1" || run_with_fallback_research
    ;;
  chatgpt-light)
    run_codex "gpt-5" || run_with_fallback_research
    ;;
  codex-fallback)
    run_with_fallback_code
    ;;
  gemini-fallback)
    run_with_fallback_research
    ;;
  *)
    echo "[ERROR] Unknown agent: $AGENT"
    echo "Available: codex, codex-spark, chatgpt, chatgpt-mini, chatgpt-light, gemini, gemini-pro"
    echo "Options:   --boot, --status, --resume, --complete <ID> <summary>"
    echo "           --brief <goal> <scope> <constraints>"
    exit 1
    ;;
esac

echo ""
echo "[LOG] $LOG_DIR/${AGENT}_${TASK_NAME}_${TIMESTAMP}.*"
echo "[QUEUE] $QUEUE_TASK_DIR/"
