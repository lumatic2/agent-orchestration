#!/usr/bin/env bash
# ============================================================
# orchestrate.sh — Dispatch tasks to worker agents
#
# Called by Claude Code to delegate work.
# Handles: agent invocation, rate limit detection, task brief generation,
#          result parsing, and persistent queue.
#
# Usage:
#   bash orchestrate.sh codex "task description or @brief_file" task-name
#   bash orchestrate.sh gemini "task description" task-name
#   bash orchestrate.sh --dry-run codex "task description" task-name
#   bash orchestrate.sh --status         # show all queue entries
#   bash orchestrate.sh --complete T001 "summary"  # manually complete a task
#   bash orchestrate.sh --cost           # today's usage per model + limits
#   bash orchestrate.sh --chain "question" agent1 [agent2...] [task-name]
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOCAL_VAULT_PATH="${LOCAL_VAULT_PATH:-${VAULT_ROOT:-$HOME/vault}}"
LOG_DIR="$REPO_DIR/logs"
QUEUE_DIR="${TMPDIR:-/tmp}/orchestrate-$$"
TEMPLATE_DIR="$REPO_DIR/templates"
AGENT_CONFIG_FILE="$REPO_DIR/agent_config.yaml"
ACTIVITY_LOG="/dev/null"
mkdir -p "$LOG_DIR" "$QUEUE_DIR" "$REPO_DIR/queue"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
now_iso() { date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || date +%Y-%m-%dT%H:%M:%S; }

# Cross-platform sed -i wrapper
sedi() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# ============================================================
# nvm PATH 보장
# ============================================================
if [[ -d "$HOME/.nvm" ]]; then
  NVM_BIN="$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V 2>/dev/null | tail -1 || ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | tail -1)"
  [[ -n "$NVM_BIN" && ":$PATH:" != *":$NVM_BIN:"* ]] && export PATH="$NVM_BIN:$PATH"
fi

# ============================================================
# Queue Helper Functions
# ============================================================

next_task_id() {
  local max=0
  for dir in "$QUEUE_DIR"/T[0-9][0-9][0-9]_*/; do
    [ -d "$dir" ] || continue
    local dirname
    dirname="$(basename "$dir")"
    local tag="${dirname%%_*}"
    local digits="${tag#T}"
    digits="${digits#0}"; digits="${digits#0}"
    local num="${digits:-0}"
    [ "$num" -gt "$max" ] && max="$num"
  done
  printf "T%03d" $((max + 1))
}

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
<!-- Agent: 발견한 사항, 결정, 막힌 지점을 여기에 기록 -->

## Checkpoint
Not started.
PROGRESS_EOF

  log_activity "$id" "created" "agent=$agent"
}

update_meta_status() {
  local dir="$1" new_status="$2"
  local extra_field="${3:-}" extra_value="${4:-}"
  local meta="$dir/meta.json"

  [ -f "$meta" ] || return 1

  sedi "s/\"status\": *\"[^\"]*\"/\"status\": \"$new_status\"/" "$meta"

  case "$new_status" in
    dispatched)
      sedi "s/\"dispatched\": *[^,]*/\"dispatched\": \"$(now_iso)\"/" "$meta"
      ;;
    completed|failed)
      sedi "s/\"completed\": *[^,]*/\"completed\": \"$(now_iso)\"/" "$meta"
      ;;
    queued)
      local count
      count=$(grep -o '"retry_count": *[0-9]*' "$meta" | grep -o '[0-9]*')
      count=$((count + 1))
      sedi "s/\"retry_count\": *[0-9]*/\"retry_count\": $count/" "$meta"
      if [ -n "$extra_value" ]; then
        sedi "s/\"queued_reason\": *[^,}]*/\"queued_reason\": \"$extra_value\"/" "$meta"
      fi
      ;;
  esac

  if [ -n "$extra_field" ] && [ "$new_status" != "queued" ]; then
    sedi "s/\"$extra_field\": *[^,}]*/\"$extra_field\": \"$extra_value\"/" "$meta"
  fi

  local task_id
  task_id=$(basename "$dir" | cut -d_ -f1)
  log_activity "$task_id" "$new_status" ""
}

log_activity() {
  local id="$1" event="$2" detail="${3:-}"
  echo "{\"ts\":\"$(now_iso)\",\"id\":\"$id\",\"event\":\"$event\",\"detail\":\"$detail\"}" >> "$ACTIVITY_LOG"
}

read_meta_field() {
  local meta="$1" field="$2"
  grep -o "\"$field\": *\"[^\"]*\"" "$meta" 2>/dev/null | sed 's/.*: *"\([^"]*\)"/\1/' || echo ""
}

read_meta_field_raw() {
  local meta="$1" field="$2"
  grep -o "\"$field\": *[^,}]*" "$meta" 2>/dev/null | sed 's/.*: *//' | tr -d '"' || echo ""
}

# ============================================================
# Core Utility Functions
# ============================================================

is_rate_limited() {
  local output="$1"
  if echo "$output" | tail -10 | grep -qEi "rate.?limit|429|too.?many.?requests|resource.?exhausted|quota.?exceeded" && ! echo "$output" | tail -5 | grep -qEi "Retrying|success|완료|saved|VAULT"; then
    return 0
  fi
  return 1
}

dispatch_guard() {
  local agent_family="$1"
  local min_gap=15
  local stamp_file="$QUEUE_DIR/.last_dispatch_${agent_family}"
  if [ -f "$stamp_file" ]; then
    local last_ts now_ts elapsed
    last_ts=$(cat "$stamp_file")
    now_ts=$(date +%s)
    elapsed=$((now_ts - last_ts))
    if [ "$elapsed" -lt "$min_gap" ]; then
      local wait_sec=$((min_gap - elapsed))
      echo "[GUARD] Waiting ${wait_sec}s before next ${agent_family} dispatch"
      sleep "$wait_sec"
    fi
  fi
  date +%s > "$stamp_file"
}

parse_codex_result() {
  local raw="$1"
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

# ============================================================
# Model Selection
# ============================================================

get_model() {
  case "$1" in
    codex)         SELECTED_MODEL="gpt-5.3-codex";   SELECTED_REASONING="auto" ;;
    codex-spark)   SELECTED_MODEL="gpt-5-codex-mini"; SELECTED_REASONING="medium" ;;
    gemini)        SELECTED_MODEL="gemini-2.5-flash"; SELECTED_REASONING="auto" ;;
    gemini-pro)    SELECTED_MODEL="gemini-2.5-pro";   SELECTED_REASONING="auto" ;;
    chatgpt)       SELECTED_MODEL="gpt-5.2";          SELECTED_REASONING="auto" ;;
    chatgpt-mini)  SELECTED_MODEL="gpt-5.1-mini";     SELECTED_REASONING="medium" ;;
    openclaw)      SELECTED_MODEL="gpt-5.4";          SELECTED_REASONING="auto" ;;
    openclaw-high) SELECTED_MODEL="gpt-5.4";          SELECTED_REASONING="auto" ;;
    *) echo "[ERROR] Unknown agent: $1"; exit 1 ;;
  esac
}

# ============================================================
# Agent Execution Functions
# ============================================================

run_codex() {
  local model="${1:-}"
  local reasoning="${2:-}"
  local log_file="$LOG_DIR/codex_${TASK_NAME}_${TIMESTAMP}.json"

  if [ -z "$model" ]; then
    echo "[ERROR] Missing Codex model for task: $TASK_NAME" >&2
    return 1
  fi

  if [ "${DRY_RUN:-false}" = "true" ]; then
    print_dry_run "$AGENT" "$model"
    return 0
  fi

  dispatch_guard "codex"
  echo "[DISPATCH] Codex ($model) — task: $TASK_NAME"

  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "dispatched"
  [ -d "${QUEUE_TASK_DIR:-}" ] && sedi "s/\"model\": *\"[^\"]*\"/\"model\": \"$model\"/" "$QUEUE_TASK_DIR/meta.json"

  local work_dir=""
  if [ -n "${QUEUE_TASK_DIR:-}" ] && [ -f "${QUEUE_TASK_DIR}/brief.md" ]; then
    local detected
    detected=$(grep -Eo '(C:/|/c/)[^\s]+' "${QUEUE_TASK_DIR}/brief.md" | head -1 | tr -d '\r')
    if [ -n "$detected" ] && [ -d "$detected" ]; then
      work_dir="$detected"
      echo "[INFO] Codex working dir: $work_dir"
    fi
  fi

  local codex_args=(
    exec
    --dangerously-bypass-approvals-and-sandbox
    --skip-git-repo-check
    -m "$model"
    --json
  )
  [ -n "$reasoning" ] && codex_args+=(-c "model_reasoning_effort=$reasoning")
  [ -n "$work_dir" ] && codex_args+=(-C "$work_dir")

  codex "${codex_args[@]}" "$TASK" > "$log_file" 2>&1 || true

  local result
  result=$(cat "$log_file")

  if is_rate_limited "$result"; then
    echo "[RATE_LIMIT] Codex hit rate limit"
    [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "queued" "queued_reason" "rate_limited"
    [ -d "${QUEUE_TASK_DIR:-}" ] && sedi "s|\"log_file\": *[^,]*|\"log_file\": \"$log_file\"|" "$QUEUE_TASK_DIR/meta.json"
    return 1
  fi

  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "completed"
  [ -d "${QUEUE_TASK_DIR:-}" ] && sedi "s|\"log_file\": *[^,]*|\"log_file\": \"$log_file\"|" "$QUEUE_TASK_DIR/meta.json"
  [ -d "${QUEUE_TASK_DIR:-}" ] && echo "$result" > "$QUEUE_TASK_DIR/result.md"

  parse_codex_result "$result"
  return 0
}

vault_check() {
  if [ "${FORCE:-false}" = "true" ]; then return 1; fi

  local pattern="${TASK_NAME}_"
  local hit
  hit=$(ssh -o ConnectTimeout=5 m4 "
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
  cached_content=$(ssh -o ConnectTimeout=5 m4 "cat '$hit'" 2>/dev/null || echo "")
  [ -z "$cached_content" ] && return 1

  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "completed"
  [ -d "${QUEUE_TASK_DIR:-}" ] && echo "$cached_content" > "$QUEUE_TASK_DIR/result.md"

  echo "[VAULT_HIT] Gemini 호출 생략 — vault 캐시 사용"
  echo ""
  echo "--- Vault Cache Result ---"
  echo "$cached_content" | sed '/^---$/,/^---$/d'
  return 0
}

run_gemini() {
  local model="${1:-}"
  local reasoning="${2:-}"
  local log_file="$LOG_DIR/gemini_${TASK_NAME}_${TIMESTAMP}.txt"

  if [ -z "$model" ]; then
    echo "[ERROR] Missing Gemini model for task: $TASK_NAME" >&2
    return 1
  fi

  if [ "${DRY_RUN:-false}" = "true" ]; then
    print_dry_run "$AGENT" "$model"
    return 0
  fi

  if vault_check; then return 0; fi

  dispatch_guard "gemini"
  echo "[DISPATCH] Gemini ($model) — task: $TASK_NAME"

  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "dispatched"
  [ -d "${QUEUE_TASK_DIR:-}" ] && sedi "s/\"model\": *\"[^\"]*\"/\"model\": \"$model\"/" "$QUEUE_TASK_DIR/meta.json"

  local tmp_prompt
  tmp_prompt="/tmp/gemini_prompt_$$.tmp"
  printf '%s' "$TASK" > "$tmp_prompt"

  node ~/.claude/plugins/gemini/scripts/gemini-companion.mjs task \
    -m "$model" \
    < "$tmp_prompt" 2>&1 \
    | grep -Ev "YOLO mode is enabled|All tool calls will be automatically approved|Loaded cached credentials|\[WARN\]|EPERM|EACCES|operation not permitted|Error getting folder structure" \
    > "$log_file" || true

  rm -f "$tmp_prompt"

  local result
  result=$(cat "$log_file")

  if is_rate_limited "$result"; then
    echo "[RATE_LIMIT] Gemini hit rate limit"
    [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "queued" "queued_reason" "rate_limited"
    [ -d "${QUEUE_TASK_DIR:-}" ] && sedi "s|\"log_file\": *[^,]*|\"log_file\": \"$log_file\"|" "$QUEUE_TASK_DIR/meta.json"
    return 1
  fi

  local clean_len
  clean_len=$(echo "$result" | grep -v "YOLO mode\|Loaded cached\|^$\|write_todos\|mark.*complete\|task.*complete\|completed.*task\|analysis.*done\|I have completed\|All tasks are complete" | wc -c)
  local has_file_save=false
  echo "$result" | grep -qiE "saved to|report is saved|file.*saved|저장했습니다|저장되었습니다" && has_file_save=true
  local has_narration=false
  local header_count narration_count
  header_count=$(echo "$result" | grep -c "^##" || true)
  narration_count=$(echo "$result" | grep -cE "^(I will|I have|Now I|Next,|Okay,|I've)" || true)
  [ "$header_count" -lt 3 ] && [ "$narration_count" -gt 3 ] && has_narration=true

  if [ "$clean_len" -lt 300 ] || [ "$has_file_save" = "true" ] || [ "$has_narration" = "true" ]; then
    echo "[WARN] Gemini returned a meta-response. Retrying once..."
    local retry_prompt
    retry_prompt="IMPORTANT: Output the full analysis content directly. Do NOT say 'I completed' or 'analysis is done'. Write everything inline now.

${TASK}"
    printf '%s' "$retry_prompt" > "$tmp_prompt"
    node ~/.claude/plugins/gemini/scripts/gemini-companion.mjs task \
      -m "$model" < "$tmp_prompt" 2>&1 \
      | grep -Ev "YOLO mode is enabled|All tool calls will be automatically approved|Loaded cached credentials|\[WARN\]|EPERM|EACCES|operation not permitted|Error getting folder structure" \
      > "$log_file" || true
    rm -f "$tmp_prompt"
    result=$(cat "$log_file")
  fi

  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "completed"
  [ -d "${QUEUE_TASK_DIR:-}" ] && sedi "s|\"log_file\": *[^,]*|\"log_file\": \"$log_file\"|" "$QUEUE_TASK_DIR/meta.json"
  [ -d "${QUEUE_TASK_DIR:-}" ] && echo "$result" > "$QUEUE_TASK_DIR/result.md"

  if [ "$NO_VAULT" != "true" ]; then
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
    ssh -o ConnectTimeout=10 m4 "mkdir -p ~/vault/${vault_dir} && cat > ~/vault/${vault_dir}/${vault_file}" << VAULTEOF
---
type: knowledge
domain: ${effective_domain}
source: gemini
generated-by: ${model}
date: $(date +%Y-%m-%d)
status: inbox
task: ${TASK_NAME}
---

$clean_result
VAULTEOF
  fi

  return 0
}

run_openclaw() {
  local thinking="${1:-medium}"
  local log_file="$LOG_DIR/openclaw_${TASK_NAME}_${TIMESTAMP}.txt"
  local ssh_prefix="source ~/.zprofile 2>/dev/null; source ~/.zshrc 2>/dev/null;"

  if [ "${DRY_RUN:-false}" = "true" ]; then
    echo "[DRY-RUN] openclaw (thinking=$thinking) — task: $TASK_NAME"
    return 0
  fi

  echo "[DISPATCH] OpenClaw (thinking=$thinking) — task: $TASK_NAME"
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "dispatched"
  : > "$log_file"

  run_openclaw_ssh() {
    local remote_cmd="$1"
    ssh m4 "${ssh_prefix} ${remote_cmd}"
  }

  parse_openclaw_json() {
    local parse_mode="$1"
    python3 -c '
import json, sys

mode = sys.argv[1]
raw = sys.stdin.read()

def load_json(text):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    for line in reversed(lines):
        try:
            return json.loads(line)
        except Exception:
            continue
    try:
        return json.loads(text)
    except Exception:
        return None

def find_value(node, keys):
    if isinstance(node, dict):
        for key, value in node.items():
            if key in keys and value not in (None, ""):
                return value
            found = find_value(value, keys)
            if found not in (None, ""):
                return found
    elif isinstance(node, list):
        for item in node:
            found = find_value(item, keys)
            if found not in (None, ""):
                return found
    return None

obj = load_json(raw)
if obj is None:
    print("")
    raise SystemExit(0)

if mode == "tab":
    value = find_value(obj, {"tabId", "tab_id", "tabID", "targetId", "target_id", "id"})
    print("" if value is None else str(value))
elif mode == "path":
    value = find_value(obj, {"path", "filePath", "file_path", "screenshotPath", "screenshot_path", "output", "file", "filename"})
    print("" if value is None else str(value))
elif mode == "text":
    value = find_value(obj, {"text", "content", "snapshot", "dom", "domText", "dom_text", "markdown", "value"})
    if value is None:
        print(json.dumps(obj, ensure_ascii=False))
    elif isinstance(value, str):
        print(value)
    else:
        print(json.dumps(value, ensure_ascii=False))
else:
    print("")
' "$parse_mode"
  }

  close_openclaw_browser() {
    run_openclaw_ssh "openclaw browser close --json" >> "$log_file" 2>&1 || true
  }

  local task_url
  task_url=$(printf '%s\n' "$TASK" | grep -Eo "https?://[^[:space:]\"'<>)]+" | head -1 || true)
  if [ -z "$task_url" ]; then
    echo "[ERROR] OpenClaw task requires a URL in TASK"
    [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "failed"
    write_shared_status "openclaw" "failed" "missing_url"
    return 1
  fi

  local open_output tab_id
  open_output=$(run_openclaw_ssh "openclaw browser open $(printf '%q' "$task_url") --json" 2>&1) || true
  echo "$open_output" >> "$log_file"
  tab_id=$(printf '%s' "$open_output" | parse_openclaw_json "tab")
  if [ -z "$tab_id" ]; then
    close_openclaw_browser
    echo "[ERROR] OpenClaw browser open failed or tabId missing"
    [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "failed"
    write_shared_status "openclaw" "failed" "open_failed"
    return 1
  fi

  local wait_output
  wait_output=$(run_openclaw_ssh "openclaw browser wait --load domcontentloaded --timeout-ms 30000 --json" 2>&1) || true
  echo "$wait_output" >> "$log_file"
  if [ -z "$wait_output" ]; then
    close_openclaw_browser
    echo "[ERROR] OpenClaw browser wait returned empty response"
    [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "failed"
    write_shared_status "openclaw" "failed" "wait_failed"
    return 1
  fi

  local screenshot_output remote_screenshot_path
  screenshot_output=$(run_openclaw_ssh "openclaw browser screenshot --json" 2>&1) || true
  echo "$screenshot_output" >> "$log_file"
  remote_screenshot_path=$(printf '%s' "$screenshot_output" | parse_openclaw_json "path")
  if [ -z "$remote_screenshot_path" ]; then
    close_openclaw_browser
    echo "[ERROR] OpenClaw browser screenshot path missing"
    [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "failed"
    write_shared_status "openclaw" "failed" "screenshot_path_missing"
    return 1
  fi

  local screenshot_dir screenshot_ext local_screenshot_path
  screenshot_dir="${QUEUE_TASK_DIR:-$LOG_DIR}"
  mkdir -p "$screenshot_dir"
  screenshot_ext="${remote_screenshot_path##*.}"
  if [ -z "$screenshot_ext" ] || [[ "$screenshot_ext" == */* ]]; then
    screenshot_ext="png"
  fi
  local_screenshot_path="${screenshot_dir}/openclaw_${TASK_NAME}_${TIMESTAMP}.${screenshot_ext}"
  if ! scp "m4:${remote_screenshot_path}" "$local_screenshot_path" >> "$log_file" 2>&1; then
    close_openclaw_browser
    echo "[ERROR] Failed to download screenshot via scp"
    [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "failed"
    write_shared_status "openclaw" "failed" "scp_failed"
    return 1
  fi

  local snapshot_output snapshot_text
  snapshot_output=$(run_openclaw_ssh "openclaw browser snapshot --json" 2>&1) || true
  echo "$snapshot_output" >> "$log_file"
  snapshot_text=$(printf '%s' "$snapshot_output" | parse_openclaw_json "text")
  if [ -z "$snapshot_text" ]; then
    snapshot_text="$snapshot_output"
  fi

  close_openclaw_browser

  local result
  result=$(cat << RESULTEOF
URL: $task_url
Tab ID: $tab_id
Screenshot: $local_screenshot_path

--- Snapshot ---
$snapshot_text
RESULTEOF
)

  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "completed"
  [ -d "${QUEUE_TASK_DIR:-}" ] && echo "$result" > "$QUEUE_TASK_DIR/result.md"
  write_shared_status "openclaw" "completed" "$result"

  echo "$result"
  return 0
}

write_shared_status() {
  local agent="$1" status="$2" summary="${3:-}"
  local shared_dir="$HOME/.openclaw/shared"
  [ -d "$shared_dir" ] || return 0
  cat > "$shared_dir/status.md" << STATUSEOF
# OpenClaw Shared Status
_orchestrate.sh 자동 업데이트_

## 마지막 업데이트
$(date '+%Y-%m-%d %H:%M:%S')

## 최근 작업
- 이름: ${TASK_NAME:-unknown}
- 에이전트: $agent
- 상태: $status
$([ -n "$summary" ] && printf '%s' "- 요약: $(echo "$summary" | head -3)")
STATUSEOF
}

# ============================================================
# Subcommands
# ============================================================

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

  echo "[ERROR] Task not found: $target_id"
  exit 1
}

do_cost() {
  local period="${1:-today}"
  python3 - "$QUEUE_DIR" "$REPO_DIR/archive/queue" "$period" "$AGENT_CONFIG_FILE" << 'PYEOF'
import json, sys
from pathlib import Path
from datetime import date, timedelta

try:
    import yaml
except ImportError:
    yaml = None

queue_dir   = Path(sys.argv[1])
archive_dir = Path(sys.argv[2])
period      = sys.argv[3] if len(sys.argv) > 3 else "today"
config_path = Path(sys.argv[4]) if len(sys.argv) > 4 else None

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

def as_int(value):
    try:
        return int(value)
    except Exception:
        return None

LIMITS = {}
if yaml is not None and config_path and config_path.exists():
    try:
        config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    except Exception:
        config = {}
    gemini_models = ((config.get("models") or {}).get("gemini") or {})
    gemini_limits = ((config.get("limits") or {}).get("gemini_pro") or {})
    shared = as_int(gemini_limits.get("shared_requests_per_day"))
    tier_limits = {
        "default": as_int(gemini_limits.get("default_per_day")) or shared,
        "heavy": as_int(gemini_limits.get("heavy_per_day")) or shared,
        "light": as_int(gemini_limits.get("light_per_day")) or shared,
    }
    for tier, model_name in gemini_models.items():
        limit = tier_limits.get(str(tier))
        if model_name and limit:
            LIMITS[str(model_name)] = limit

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

model_counts  = {}
agent_counts  = {}
total = completed_cnt = pending_cnt = 0

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

print(f"\n=== Agent Usage ({period_label}) ===\n")

if not model_counts:
    print("  (해당 기간 완료된 작업 없음)")
else:
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

    print(f"\n  [에이전트 유형별]")
    total_calls = sum(agent_counts.values())
    for atype, count in sorted(agent_counts.items(), key=lambda x: -x[1]):
        pct = count / total_calls * 100 if total_calls else 0
        bar_len = min(int(pct / 5), 20)
        bar = "█" * bar_len
        print(f"  {atype:<20} {count:>4}회  {bar} {pct:.0f}%")

print(f"\n  큐 전체: {total}개 (완료 {completed_cnt} / 대기 {pending_cnt})")
print("  주간: bash orchestrate.sh --cost week")
print("  전체: bash orchestrate.sh --cost all")
PYEOF
  exit 0
}

do_chain() {
  shift
  QUESTION="${1:?Usage: orchestrate.sh --chain \"question\" agent1 [agent2...]}"
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
# Main Dispatcher
# ============================================================

case "${1:-}" in
  --status)  do_status "${2:-}"; exit 0 ;;
  --complete) shift; do_complete "$@"; exit 0 ;;
  --cost)    do_cost "${2:-today}"; exit 0 ;;
  --chain)   do_chain "$@"; exit 0 ;;
  run)       shift; python3 "$SCRIPT_DIR/run_blueprint.py" "$@"; exit $? ;;
esac

# --- Parse arguments ---
DRY_RUN="false"
VAULT_DOMAIN=""
FORCE="${FORCE:-false}"
NO_VAULT="${NO_VAULT:-false}"
while [[ "${1:-}" == --* ]]; do
  case "${1:-}" in
    --dry-run)  DRY_RUN="true"; shift ;;
    --vault)    VAULT_DOMAIN="${2:-inbox}"; shift 2 ;;
    --no-vault) NO_VAULT="true"; shift ;;
    --force)    FORCE="true"; shift ;;
    *) break ;;
  esac
done

AGENT="${1:?Usage: orchestrate.sh [--dry-run] <agent> <task|@file> [task_name]}"
TASK="${2:?Usage: orchestrate.sh [--dry-run] <agent> <task|@file> [task_name]}"
TASK_NAME="${3:-unnamed}"

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
  codex|codex-spark)
    get_model "$AGENT"
    run_codex "$SELECTED_MODEL" "$SELECTED_REASONING"
    ;;
  gemini|gemini-pro)
    get_model "$AGENT"
    run_gemini "$SELECTED_MODEL" "$SELECTED_REASONING"
    ;;
  chatgpt|chatgpt-mini)
    get_model "$AGENT"
    run_codex "$SELECTED_MODEL" "$SELECTED_REASONING"
    ;;
  openclaw|openclaw-high)
    get_model "$AGENT"
    run_openclaw "$SELECTED_REASONING"
    ;;
  *)
    echo "[ERROR] Unknown agent: $AGENT"
    echo "Available: codex, codex-spark, chatgpt, chatgpt-mini, gemini, gemini-pro, openclaw, openclaw-high"
    exit 1
    ;;
esac

if [ "${DRY_RUN:-false}" = "true" ]; then
  exit 0
fi

echo ""
echo "[LOG] $LOG_DIR/${AGENT}_${TASK_NAME}_${TIMESTAMP}.*"
