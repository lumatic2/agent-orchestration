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
#   bash orchestrate.sh --dry-run codex "task description" task-name
#   bash orchestrate.sh codex --json '{"goal":"...","scope":"..."}' task-name
#   bash orchestrate.sh schema [agent] [--json]
#   bash orchestrate.sh run <blueprint_file> [--var key=value ...]
#   bash orchestrate.sh --brief "goal" "scope" "constraints"
#   bash orchestrate.sh --boot           # scan queue on session start
#   bash orchestrate.sh --status         # show all queue entries
#   bash orchestrate.sh --resume         # re-dispatch oldest pending/queued
#   bash orchestrate.sh --complete T001 "summary"  # manually complete a task
#   bash orchestrate.sh --cost           # today's usage per model + limits
#   bash orchestrate.sh --clean [--dry]  # archive completed queue entries
#   bash orchestrate.sh --chain "question" agent1 [agent2...] [task-name] [--save] [--pro]
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOCAL_VAULT_PATH="${LOCAL_VAULT_PATH:-$HOME/vault}" # Default to ~/vault, user can override
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

  cat > "$dir/progress.md" << PROGRESS_EOF
# Progress: ${name}
Created: ${ISO_NOW}
Task ID: ${id}

## Phases
- [ ] 탐색 완료
- [ ] 수정 완료
- [ ] 검증 완료

## Notes
<!-- Codex: 발견한 사항, 결정, 막힌 지점을 여기에 기록 -->

## Checkpoint (resume 시 여기서부터)
<!-- Codex: 마지막으로 완료한 단계와 다음 시작 지점 기록 -->
Not started.
PROGRESS_EOF

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
  # Check only last 30 lines to avoid false positives from file contents read by agents
  if echo "$output" | tail -10 | grep -qEi "rate.?limit|429|too.?many.?requests" && ! echo "$output" | tail -5 | grep -qEi "Retrying|success|완료|saved|VAULT"; then
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
  local min_gap=15
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

print_dry_run() {
  local agent="$1" model="$2"
  echo "=== DRY RUN ==="
  echo "Agent:   $agent"
  echo "Model:   $model"
  echo "Task:    $TASK_NAME"
  echo "Brief:"
  echo "---"
  echo "$TASK"
  echo "---"
  echo "(실제 실행 없음)"
}

json_to_brief() {
  local json_input="$1"
  PYTHONIOENCODING=utf-8 python3 - "$json_input" << 'PYEOF'
import json
import sys

def fail(msg):
    print(f"[ERROR] {msg}", file=sys.stderr)
    sys.exit(1)

raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception as e:
    fail(f"Invalid JSON for --json: {e}")

if not isinstance(data, dict):
    fail("--json input must be a JSON object")

goal = str(data.get("goal", "")).strip()
if not goal:
    fail("--json requires field: goal")

def clean(key):
    val = data.get(key)
    if val is None:
        return ""
    return str(val).strip()

scope = clean("scope")
constraints = clean("constraints")
output = clean("output")
context = clean("context")
done_criteria = data.get("done_criteria")

lines = []
lines += ["## Goal", goal, ""]

if scope:
    lines += ["## Scope", f"- {scope}", ""]

if constraints:
    lines += ["## Constraints", f"- {constraints}", ""]

if output:
    lines += ["## Output Format", f"- {output}", ""]

if context:
    lines += ["## Context", f"- {context}", ""]

lines += ["## Done Criteria"]
if done_criteria is None or (isinstance(done_criteria, str) and not done_criteria.strip()):
    lines += ["- [ ] Task completed successfully"]
elif isinstance(done_criteria, list):
    items = [str(x).strip() for x in done_criteria if str(x).strip()]
    if not items:
        lines += ["- [ ] Task completed successfully"]
    else:
        lines += [f"- [ ] {item}" for item in items]
else:
    lines += [f"- [ ] {str(done_criteria).strip()}"]

print("\n".join(lines))
PYEOF
}

do_schema() {
  local target="${1:-}"
  local output_json="false"

  if [ "$target" = "--json" ]; then
    output_json="true"
    target=""
  elif [ "${2:-}" = "--json" ]; then
    output_json="true"
  fi

  if [ "$output_json" = "true" ]; then
    if [ -n "$target" ]; then
      case "$target" in
        codex)
          cat << 'JSON_EOF'
{"name":"codex","models":["gpt-5.3-codex","gpt-5.3-codex-spark"],"default_model":"gpt-5.3-codex","use_for":["Code generation, refactoring, test loops","4+ files or 50+ lines of code"],"flags":{"--dry-run":"Validate without executing","--json <JSON>":"Structured task input (goal, scope, constraints, output)"},"input":{"task":"string (required) — task description or @filepath or --json","task_name":"string (optional, default: unnamed)"},"quota":"most generous (use first for code tasks)","fallback":"queues on rate limit, retry with --resume"}
JSON_EOF
          ;;
        codex-spark)
          cat << 'JSON_EOF'
{"name":"codex-spark","models":["gpt-5.3-codex-spark"],"default_model":"gpt-5.3-codex-spark","use_for":["Quick edits, small patches, fast iterations"],"flags":{"--dry-run":"Validate without executing","--json <JSON>":"Structured task input (goal, scope, constraints, output)"},"input":{"task":"string (required) — task description or @filepath or --json","task_name":"string (optional, default: unnamed)"},"quota":"high","fallback":"codex fallback chain, retry with --resume"}
JSON_EOF
          ;;
        gemini)
          cat << 'JSON_EOF'
{"name":"gemini","models":["gemini-2.5-flash"],"default_model":"gemini-2.5-flash","use_for":["Research, summarization, lightweight analysis"],"flags":{"--dry-run":"Validate without executing","--json <JSON>":"Structured task input (goal, scope, constraints, output)"},"input":{"task":"string (required) — task description or @filepath or --json","task_name":"string (optional, default: unnamed)"},"quota":"moderate","fallback":"codex fallback on rate limit"}
JSON_EOF
          ;;
        gemini-pro)
          cat << 'JSON_EOF'
{"name":"gemini-pro","models":["gemini-2.5-pro"],"default_model":"gemini-2.5-pro","use_for":["Deep analysis, complex reasoning tasks"],"flags":{"--dry-run":"Validate without executing","--json <JSON>":"Structured task input (goal, scope, constraints, output)"},"input":{"task":"string (required) — task description or @filepath or --json","task_name":"string (optional, default: unnamed)"},"quota":"lower than flash","fallback":"codex fallback on rate limit"}
JSON_EOF
          ;;
        *)
          echo "[ERROR] Unknown agent for schema: $target"
          exit 1
          ;;
      esac
      exit 0
    fi

    cat << 'JSON_EOF'
{
  "agents": [
    {"name":"codex","default_model":"gpt-5.3-codex","models":["gpt-5.3-codex","gpt-5.3-codex-spark"],"use_for":"code generation, refactoring, 4+ files or 50+ lines"},
    {"name":"codex-spark","default_model":"gpt-5.3-codex-spark","models":["gpt-5.3-codex-spark"],"use_for":"quick edits, small patches"},
    {"name":"gemini","default_model":"gemini-2.5-flash","models":["gemini-2.5-flash"],"use_for":"research, doc analysis, 1500 req/day"},
    {"name":"gemini-pro","default_model":"gemini-2.5-pro","models":["gemini-2.5-pro"],"use_for":"deep analysis, max 100/day — use sparingly"}
  ],
  "dispatch": {
    "usage": "orchestrate.sh <agent> \"<task>\" <task-name> [--dry-run]",
    "flags": {
      "--dry-run": "validate without executing",
      "--pro": "use gemini-pro instead of flash",
      "--save": "save result to vault",
      "--resume": "re-attach to existing task by name"
    }
  },
  "system": {
    "--boot":     {"description":"scan queue on session start, re-dispatch stale tasks","returns":"pending count"},
    "--status":   {"description":"show all queue entries","flags":{"--json":"machine-readable JSON output"},"returns":"table or {total,pending,queued,dispatched,completed,tasks[]}"},
    "--resume":   {"description":"re-dispatch oldest pending/queued task","returns":"dispatch result"},
    "--complete": {"usage":"--complete <ID> <summary>","description":"manually mark task as completed"},
    "--cost":     {"description":"today's usage per model + limits","returns":"cost table"},
    "--clean":    {"usage":"--clean [--dry]","description":"archive completed queue entries"},
    "--chain":    {"usage":"--chain \"question\" agent1 [agent2...] [task-name]","description":"pipe output of one agent to next"},
    "run":        {"usage":"run <blueprint_file> [--var key=value ...]","description":"execute YAML blueprint pipeline"}
  },
  "queue": {
    "location": "queue/T###_<name>/",
    "files": {
      "meta.json":   "dispatch status, retry count, timestamps",
      "brief.md":    "task spec (goal, scope, context budget, stop triggers)",
      "progress.md": "phase checkpoints, notes, resume point",
      "result.md":   "agent output"
    },
    "statuses": ["pending","dispatched","queued","completed"]
  }
}
JSON_EOF
    exit 0
  fi

  if [ -z "$target" ]; then
    cat << 'SCHEMA_EOF'
=== Agent Schema ===

- codex
- codex-spark
- gemini
- gemini-pro

Usage:
  orchestrate.sh schema
  orchestrate.sh schema codex
  orchestrate.sh schema gemini
  orchestrate.sh schema --json
  orchestrate.sh run blueprints/slides.yaml --var topic=커피
SCHEMA_EOF
    exit 0
  fi

  case "$target" in
    codex)
      cat << 'SCHEMA_EOF'
=== Agent Schema: codex ===

name:        codex
models:
  - gpt-5.3-codex (default, heavy tasks)
  - gpt-5.3-codex-spark (quick edits)
use_for:
  - Code generation, refactoring, test loops
  - 4+ files or 50+ lines of code
flags:
  --dry-run     : Validate without executing
  --json <JSON> : Structured task input (goal, scope, constraints, output)
input:
  task:         string (required) — task description or @filepath or --json
  task-name:    string (optional, default: unnamed)
quota:          most generous (use first for code tasks)
fallback:       queues on rate limit, retry with --resume

examples:
  orchestrate.sh codex "리팩토링 작업" task-name
  orchestrate.sh codex @brief.md task-name
  orchestrate.sh codex --json '{"goal":"...","scope":"..."}' task-name
SCHEMA_EOF
      ;;
    codex-spark)
      cat << 'SCHEMA_EOF'
=== Agent Schema: codex-spark ===

name:        codex-spark
models:
  - gpt-5.3-codex-spark (default, quick edits)
use_for:
  - Quick edits, small patches, fast iterations
flags:
  --dry-run     : Validate without executing
  --json <JSON> : Structured task input (goal, scope, constraints, output)
input:
  task:         string (required) — task description or @filepath or --json
  task-name:    string (optional, default: unnamed)
quota:          high
fallback:       codex fallback chain, retry with --resume

examples:
  orchestrate.sh codex-spark "빠른 수정" task-name
SCHEMA_EOF
      ;;
    gemini)
      cat << 'SCHEMA_EOF'
=== Agent Schema: gemini ===

name:        gemini
models:
  - gemini-2.5-flash (default)
use_for:
  - Research, summarization, lightweight analysis
flags:
  --dry-run     : Validate without executing
  --json <JSON> : Structured task input (goal, scope, constraints, output)
input:
  task:         string (required) — task description or @filepath or --json
  task-name:    string (optional, default: unnamed)
quota:          moderate
fallback:       Codex fallback on rate limit

examples:
  orchestrate.sh gemini "최신 라이브러리 조사" research-task
SCHEMA_EOF
      ;;
    gemini-pro)
      cat << 'SCHEMA_EOF'
=== Agent Schema: gemini-pro ===

name:        gemini-pro
models:
  - gemini-2.5-pro (default, deep analysis)
use_for:
  - Deep analysis, complex reasoning tasks
flags:
  --dry-run     : Validate without executing
  --json <JSON> : Structured task input (goal, scope, constraints, output)
input:
  task:         string (required) — task description or @filepath or --json
  task-name:    string (optional, default: unnamed)
quota:          lower than flash
fallback:       Codex fallback on rate limit

examples:
  orchestrate.sh gemini-pro "심층 분석" analysis-task
SCHEMA_EOF
      ;;
    *)
      echo "[ERROR] Unknown agent for schema: $target"
      exit 1
      ;;
  esac
  exit 0
}

# --- Run Codex ---
run_codex() {
  local model="${1:-gpt-5.3-codex}"
  local log_file="$LOG_DIR/codex_${TASK_NAME}_${TIMESTAMP}.json"

  if [ "${DRY_RUN:-false}" = "true" ]; then
    print_dry_run "$AGENT" "$model"
    return 0
  fi

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

# --- Vault check (skip Gemini if recent cached result exists) ---
vault_check() {
  # Returns 0 = vault hit (use cache, skip Gemini), 1 = no hit (run Gemini)
  if [ "${FORCE:-false}" = "true" ]; then return 1; fi

  local pattern="${TASK_NAME}_"
  local hit
  hit=$(ssh -o ConnectTimeout=5 m1 "
    cutoff=\$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d 2>/dev/null || echo '1970-01-01')
    find ~/vault -name '${pattern}*.md' -type f 2>/dev/null | while IFS= read -r f; do
      fname=\$(basename \"\$f\" .md)
      fdate=\${fname##*_}
      [[ \"\$fdate\" > \"\$cutoff\" || \"\$fdate\" == \"\$cutoff\" ]] && echo \"\$f\" && break
    done
  " 2>/dev/null || echo "")

  [ -z "$hit" ] && return 1

  echo "[VAULT_HIT] 기존 리서치 발견 (7일 이내): $hit"

  local cached_content
  cached_content=$(ssh -o ConnectTimeout=5 m1 "cat '$hit'" 2>/dev/null || echo "")
  [ -z "$cached_content" ] && return 1

  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "completed"
  [ -d "${QUEUE_TASK_DIR:-}" ] && echo "$cached_content" > "$QUEUE_TASK_DIR/result.md"

  echo "[VAULT_HIT] Gemini 호출 생략 — vault 캐시 사용 (--force로 강제 재실행 가능)"
  echo ""
  echo "--- Vault Cache Result ---"
  echo "$cached_content" | sed '/^---$/,/^---$/d'
  return 0
}

# --- Run Gemini ---
run_gemini() {
  local model="${1:-gemini-2.5-flash}"
  local log_file="$LOG_DIR/gemini_${TASK_NAME}_${TIMESTAMP}.txt"

  if [ "${DRY_RUN:-false}" = "true" ]; then
    print_dry_run "$AGENT" "$model"
    return 0
  fi

  # Vault check — skip Gemini if recent result cached in vault
  if vault_check; then return 0; fi

  dispatch_guard "gemini"
  echo "[DISPATCH] Gemini ($model) — task: $TASK_NAME"

  # Update queue status to dispatched
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "dispatched"
  [ -d "${QUEUE_TASK_DIR:-}" ] && sedi "s/\"model\": *\"[^\"]*\"/\"model\": \"$model\"/" "$QUEUE_TASK_DIR/meta.json"

  # Write directly to file to avoid shell variable truncation
  gemini \
    --yolo \
    -m "$model" \
    -p "$TASK" 2>&1 \
    | grep -Ev "YOLO mode is enabled|All tool calls will be automatically approved|Loaded cached credentials|\[WARN\]|EPERM|EACCES|operation not permitted|Error getting folder structure" \
    > "$log_file" || true

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

  # Save to vault — always (VAULT_DOMAIN defaults to "research")
  local effective_domain="${VAULT_DOMAIN:-research}"
  local vault_dir
  if [ "$effective_domain" = "inbox" ]; then
    vault_dir="00-inbox"
  else
    vault_dir="10-knowledge/${effective_domain}"
  fi
  local vault_file="${TASK_NAME}_$(date +%Y-%m-%d).md"
  local clean_result
  clean_result=$(echo "$result" | grep -v "YOLO mode\|Loaded cached\|^$")
  ssh m1 "mkdir -p ~/vault/${vault_dir} && cat > ~/vault/${vault_dir}/${vault_file}" << VAULTEOF
---
type: knowledge
domain: ${effective_domain}
source: gemini
generated-by: ${model}
date: $(date +%Y-%m-%d)
status: inbox
task: ${TASK_NAME}
---

${clean_result}
VAULTEOF
  echo "[VAULT] Saved → ~/vault/${vault_dir}/${vault_file}"

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

  echo "[QUEUED] Codex rate-limited. Task queued for retry."
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "queued" "queued_reason" "codex_rate_limited"
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
  # ── Self-update: pull repo first, reexec if orchestrate.sh changed ──
  if [ "${_BOOT_SELF_UPDATED:-0}" != "1" ]; then
    local self_hash
    self_hash=$(md5sum "$0" 2>/dev/null || shasum "$0")
    git -C "$REPO_DIR" pull --rebase --quiet 2>/dev/null || true
    local new_hash
    new_hash=$(md5sum "$0" 2>/dev/null || shasum "$0")
    if [ "$self_hash" != "$new_hash" ]; then
      echo "[INFO] orchestrate.sh 업데이트됨 — 재실행..."
      _BOOT_SELF_UPDATED=1 exec bash "$0" --boot
    fi
    echo "[OK] orchestrate.sh 최신"
  fi

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

  # ── Auto-pull: 모든 레포 최신화 ──────────────────────────────
  echo ""
  echo "=== Auto-pull ==="
  # 기기별 레포 목록 (공백 구분, HOME 기준)
  case "$(hostname)" in
    DESKTOP*|PC*|*windows*|LUMA*)   # Windows
      PULL_REPOS=(
        "$HOME/projects/agent-orchestration"
        "$HOME/Desktop/content-automation"
        "$HOME/Desktop/portfolio"
      ) ;;
    *luma3*|*Macmini*luma3*|*m4*)   # M4 (회사)
      PULL_REPOS=(
        "$HOME/vault"
        "$HOME/projects/agent-orchestration"
        "$HOME/Desktop/content-automation"
      ) ;;
    *[Aa]ir*|*MacBook*)             # MacBook Air
      PULL_REPOS=(
        "$HOME/vault"
        "$HOME/projects/agent-orchestration"
      ) ;;
    *luma2*|*luma2s*)               # M1 (~/projects/)
      PULL_REPOS=(
        "$HOME/vault"
        "$HOME/projects/agent-orchestration"
        "$HOME/Desktop/content-automation"
      ) ;;
    *)                              # fallback
      PULL_REPOS=(
        "$HOME/vault"
        "$HOME/projects/agent-orchestration"
        "$HOME/Desktop/content-automation"
      ) ;;
  esac

  for repo in "${PULL_REPOS[@]}"; do
    [ -d "$repo/.git" ] || continue
    # self-update 단계에서 이미 pull한 agent-orchestration은 스킵
    [ "$repo" = "$REPO_DIR" ] && [ "${_BOOT_SELF_UPDATED:-0}" = "1" ] && echo "[OK] $(basename "$repo") 최신 (self-update 완료)" && continue
    local branch
    branch=$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || echo "HEAD")
    git -C "$repo" fetch origin "$branch" --quiet 2>/dev/null || { echo "[SKIP] $repo — fetch 실패 (오프라인?)"; continue; }
    local behind
    behind=$(git -C "$repo" rev-list HEAD..origin/"$branch" --count 2>/dev/null || echo 0)
    if [ "$behind" -gt 0 ]; then
      # 로컬 변경 있으면 stash 후 pull
      local dirty
      dirty=$(git -C "$repo" status --porcelain 2>/dev/null | grep -c "^[^?]" || true)
      [ "$dirty" -gt 0 ] && git -C "$repo" stash push -m "auto-boot-stash" --quiet 2>/dev/null
      if git -C "$repo" pull --ff-only origin "$branch" --quiet 2>/dev/null; then
        echo "[PULLED] $(basename "$repo") ← $behind commit(s)"
      else
        echo "[WARN] $(basename "$repo") — fast-forward 불가, 수동 확인 필요"
      fi
      [ "$dirty" -gt 0 ] && git -C "$repo" stash pop --quiet 2>/dev/null || true
    else
      echo "[OK] $(basename "$repo") 최신"
    fi
  done

  # Skills 자동 배포 (git pull 후 repo/skills/ → ~/.claude/commands/)
  local skills_src="$SCRIPT_DIR/../skills"
  if [ -d "$skills_src" ]; then
    cp "$skills_src"/*.md "$HOME/.claude/commands/" 2>/dev/null || true
  fi

  # Knowledge file refresh (최근 1일 이내 갱신된 경우 스킵)
  REFRESH_SCRIPT="$SCRIPT_DIR/refresh_knowledge.sh"
  REFRESH_STAMP="$SCRIPT_DIR/.refresh_last_run"
  if [ -f "$REFRESH_SCRIPT" ]; then
    SKIP_REFRESH=false
    if [ -f "$REFRESH_STAMP" ]; then
      LAST=$(cat "$REFRESH_STAMP")
      NOW_SEC=$(date +%s)
      if [ $(( NOW_SEC - LAST )) -lt 86400 ]; then
        SKIP_REFRESH=true
      fi
    fi
    if [ "$SKIP_REFRESH" = false ]; then
      echo ""
      echo "=== Knowledge Refresh ==="
      bash "$REFRESH_SCRIPT" --agent all 2>&1 | grep -E "✅|⚠️|갱신|ERROR" || true
      date +%s > "$REFRESH_STAMP"
    else
      echo "Knowledge files up-to-date (갱신 후 24h 미경과)."
    fi
  fi

  exit 0
}

do_status() {
  local json_mode=0
  [ "${1:-}" = "--json" ] && json_mode=1

  if [ "$json_mode" = "1" ]; then
    local entries="" total=0 pending=0 queued=0 completed=0 dispatched=0
    for dir in "$QUEUE_DIR"/T[0-9][0-9][0-9]_*/; do
      [ -d "$dir" ] || continue
      local meta="$dir/meta.json"
      [ -f "$meta" ] || continue

      local id name status agent retries created
      id=$(read_meta_field "$meta" "id")
      name=$(read_meta_field "$meta" "name")
      status=$(read_meta_field "$meta" "status")
      agent=$(read_meta_field "$meta" "agent")
      retries=$(read_meta_field_raw "$meta" "retry_count")
      created=$(read_meta_field "$meta" "created")

      [ -n "$entries" ] && entries="$entries,"
      entries="$entries{\"id\":\"$id\",\"name\":\"$name\",\"status\":\"$status\",\"agent\":\"$agent\",\"retries\":$retries,\"created\":\"$created\"}"

      total=$((total + 1))
      case "$status" in
        pending)    pending=$((pending + 1)) ;;
        queued)     queued=$((queued + 1)) ;;
        completed)  completed=$((completed + 1)) ;;
        dispatched) dispatched=$((dispatched + 1)) ;;
      esac
    done
    echo "{\"total\":$total,\"pending\":$pending,\"queued\":$queued,\"dispatched\":$dispatched,\"completed\":$completed,\"tasks\":[$entries]}"
  else
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
  fi
  exit 0
}

do_set_status() {
  local task_id="${1:?Usage: orchestrate.sh set_status <TASK_ID> <TASK_NAME> <NEW_STATUS> [EXTRA_FIELD] [EXTRA_VALUE]}"
  local task_name="${2:?Usage: orchestrate.sh set_status <TASK_ID> <TASK_NAME> <NEW_STATUS> [EXTRA_FIELD] [EXTRA_VALUE]}"
  local new_status="${3:?Usage: orchestrate.sh set_status <TASK_ID> <TASK_NAME> <NEW_STATUS> [EXTRA_FIELD] [EXTRA_VALUE]}"
  local extra_field="${4:-}"
  local extra_value="${5:-}"

  local task_dir="$QUEUE_DIR/${task_id}_${task_name}"
  if [ ! -d "$task_dir" ]; then
    echo "[ERROR] Task directory not found: $task_dir"
    exit 1
  fi

  update_meta_status "$task_dir" "$new_status" "$extra_field" "$extra_value"
  echo "[STATUS_UPDATE] Task $task_id ($task_name) status set to '$new_status'."
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

# ─── 응답 품질 요약 ───────────────────────────────────────────
feedback_log = Path(sys.argv[1]).parent / "logs" / "feedback.jsonl"
if feedback_log.exists() and feedback_log.stat().st_size > 0:
    fb_records = []
    with open(feedback_log) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
                if r.get("ts", "")[:10] >= cutoff:
                    fb_records.append(r)
            except Exception:
                pass

    if fb_records:
        ratings = [r["rating"] for r in fb_records]
        avg = sum(ratings) / len(ratings)
        low = [r for r in fb_records if r["rating"] <= 2]
        top = [r for r in fb_records if r["rating"] == 5]

        print(f"\n  [응답 품질 — {len(fb_records)}건 평가]")
        stars = "★" * round(avg) + "☆" * (5 - round(avg))
        print(f"  평균 {avg:.1f}점 {stars}  |  최고 {len(top)}건  |  개선필요 {len(low)}건")

        # 에이전트별 평균 (낮은 것만 경고)
        by_agent = {}
        for r in fb_records:
            key = r.get("expert") or r.get("agent") or "?"
            by_agent.setdefault(key, []).append(r["rating"])
        needs_work = [(k, sum(v)/len(v)) for k, v in by_agent.items() if sum(v)/len(v) < 3.0]
        if needs_work:
            print(f"  ⚠️  개선 필요: " + ", ".join(f"{k}({a:.1f}점)" for k, a in sorted(needs_work, key=lambda x: x[1])))

        print(f"  상세: bash feedback.sh --stats")
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

do_chain() {
  # Usage: orchestrate.sh --chain "question" agent1 [agent2...] [task-name] [--save] [--pro] [--title "제목"]
  shift  # remove --chain
  QUESTION="${1:?Usage: orchestrate.sh --chain \"question\" agent1 [agent2...] [task-name]}"
  shift

  local AGENTS=()
  local TASK_NAME="chain"
  local CHAIN_FLAGS=()
  local PREV_ARG=""

  for arg in "$@"; do
    case "$arg" in
      --save|--pro) CHAIN_FLAGS+=("$arg") ;;
      --title)      CHAIN_FLAGS+=("$arg") ;;
      *)
        if [ "$PREV_ARG" = "--title" ]; then
          CHAIN_FLAGS+=("$arg")
        elif [[ "$arg" == tax || "$arg" == expert:* || "$arg" == law || "$arg" == law:* ]]; then
          AGENTS+=("$arg")
        else
          TASK_NAME="$arg"
        fi
        ;;
    esac
    PREV_ARG="$arg"
  done

  if [ ${#AGENTS[@]} -eq 0 ]; then
    echo "[ERROR] --chain requires at least one agent (tax, expert:<type>, law)"
    exit 1
  fi

  local CHAIN_ID
  CHAIN_ID=$(next_task_id)
  create_queue_entry "$CHAIN_ID" "$TASK_NAME" "chain" "$QUESTION"
  local CHAIN_DIR="$QUEUE_DIR/${CHAIN_ID}_${TASK_NAME}"
  update_meta_status "$CHAIN_DIR" "dispatched"
  echo "[QUEUE] Created $CHAIN_ID ($TASK_NAME) — chain: ${AGENTS[*]}"

  if bash "$SCRIPT_DIR/chain.sh" "$QUESTION" "${AGENTS[@]}" ${CHAIN_FLAGS[@]+"${CHAIN_FLAGS[@]}"}; then
    update_meta_status "$CHAIN_DIR" "completed"
    log_activity "CHAIN" "completed" "id=$CHAIN_ID agents=${AGENTS[*]}"
    echo "[QUEUE] $CHAIN_ID completed"
  else
    update_meta_status "$CHAIN_DIR" "failed"
    log_activity "CHAIN" "failed" "id=$CHAIN_ID agents=${AGENTS[*]}"
    echo "[ERROR] Chain failed — $CHAIN_ID"
    exit 1
  fi
  exit 0
}

# ============================================================
# Handle subcommands before main dispatch
# ============================================================

case "${1:-}" in
  run)        shift; python "$SCRIPT_DIR/run_blueprint.py" "$@"; exit $? ;;
  schema)     shift; do_schema "$@" ;;
  --boot)     do_boot ;;
  --status)   shift; do_status "${1:-}" ;;
  --resume)   do_resume ;;
  --complete) shift; do_complete "$@" ;;
  --cost)     do_cost ;;
  --clean)    shift; do_clean "${1:-}" ;;
  --chain)    do_chain "$@" ;;
  set_status) shift; do_set_status "$@" ;;
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
DRY_RUN="false"
VAULT_DOMAIN=""
FORCE="false"
while [[ "${1:-}" == --* ]]; do
  case "${1:-}" in
    --dry-run) DRY_RUN="true"; shift ;;
    --vault)   VAULT_DOMAIN="${2:-inbox}"; shift 2 ;;
    --force)   FORCE="true"; shift ;;
    *) break ;;
  esac
done

AGENT="${1:?Usage: orchestrate.sh [--dry-run] <agent> <task|--json JSON> [task_name]}"

if [[ "${2:-}" == "--json" ]]; then
  JSON_INPUT="${3:-}"
  if [ -z "$JSON_INPUT" ]; then
    echo "[ERROR] Missing JSON payload after --json"
    exit 1
  fi
  if ! TASK="$(json_to_brief "$JSON_INPUT")"; then
    exit 1
  fi
  TASK_NAME="${4:-unnamed}"
else
  TASK="${2:?Usage: orchestrate.sh [--dry-run] <agent> <task|--json JSON> [task_name]}"
  TASK_NAME="${3:-unnamed}"
fi

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
if [ "$DRY_RUN" != "true" ]; then
  QUEUE_TASK_ID=$(next_task_id)
  create_queue_entry "$QUEUE_TASK_ID" "$TASK_NAME" "$AGENT" "$TASK"
  QUEUE_TASK_DIR="$QUEUE_DIR/${QUEUE_TASK_ID}_${TASK_NAME}"
  echo "[QUEUE] Created $QUEUE_TASK_ID ($TASK_NAME)"
fi

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
    echo "Options:   run <blueprint_file> [--var key=value ...]"
    echo "           --boot, --status, --resume, --complete <ID> <summary>, schema [agent] [--json]"
    echo "           --brief <goal> <scope> <constraints>"
    echo "           --dry-run, --json '{\"goal\":\"...\"}'"
    exit 1
    ;;
esac

if [ "${DRY_RUN:-false}" = "true" ]; then
  exit 0
fi

echo ""
echo "[LOG] $LOG_DIR/${AGENT}_${TASK_NAME}_${TIMESTAMP}.*"
echo "[QUEUE] $QUEUE_TASK_DIR/"
