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
source "$SCRIPT_DIR/env.sh"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOCAL_VAULT_PATH="${LOCAL_VAULT_PATH:-${VAULT_ROOT:-$HOME/vault}}"
LOG_DIR="$REPO_DIR/logs"
QUEUE_DIR="${TMPDIR:-/tmp}/orchestrate-$$"
TEMPLATE_DIR="$REPO_DIR/templates"
AGENT_CONFIG_FILE="$REPO_DIR/agent_config.yaml"
ACTIVITY_LOG="/dev/null"
ACTIVE_MODE_FILE="$REPO_DIR/queue/.active_mode"
PERSIST_MODE_FILE="$REPO_DIR/queue/.persist_mode"
mkdir -p "$LOG_DIR" "$QUEUE_DIR" "$REPO_DIR/queue"

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
# nvm PATH 보장 (비대화형 쉘에서 .zshrc 미로드 시 대비)
# ============================================================
if [[ -d "$HOME/.nvm" ]]; then
  NVM_BIN="$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V 2>/dev/null | tail -1 || ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | tail -1)"
  [[ -n "$NVM_BIN" && ":$PATH:" != *":$NVM_BIN:"* ]] && export PATH="$NVM_BIN:$PATH"
fi

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

get_default_mode() {
  python3 - "$AGENT_CONFIG_FILE" << 'PYEOF'
import sys
from pathlib import Path
try:
    import yaml  # type: ignore
except ImportError:
    print("full")
    raise SystemExit(0)

config_path = Path(sys.argv[1])
try:
    config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
except Exception:
    config = {}

default_mode = str(config.get("default_mode") or "full").strip() or "full"
print(default_mode)
PYEOF
}

mode_exists() {
  local mode_name="$1"
  python3 - "$AGENT_CONFIG_FILE" "$mode_name" << 'PYEOF'
import sys
from pathlib import Path
try:
    import yaml  # type: ignore
except ImportError:
    raise SystemExit(1)

config = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8")) or {}
mode_name = (sys.argv[2] or "").strip()
modes = config.get("modes") or {}
raise SystemExit(0 if mode_name in modes else 1)
PYEOF
}

get_active_mode() {
  local candidate=""
  if [ -f "$ACTIVE_MODE_FILE" ]; then
    candidate="$(tr -d '[:space:]' < "$ACTIVE_MODE_FILE" 2>/dev/null || true)"
  fi
  if [ -n "$candidate" ] && mode_exists "$candidate" >/dev/null 2>&1; then
    echo "$candidate"
    return
  fi
  get_default_mode
}

set_active_mode() {
  local mode_name="$1"
  local reason="${2:-manual}"
  if ! mode_exists "$mode_name" >/dev/null 2>&1; then
    return 1
  fi
  local prev_mode
  prev_mode="$(get_active_mode)"
  echo "$mode_name" > "$ACTIVE_MODE_FILE"
  log_activity "MODE" "mode_change" "from=$prev_mode to=$mode_name reason=$reason"
}

list_modes() {
  python3 - "$AGENT_CONFIG_FILE" << 'PYEOF'
import sys
from pathlib import Path
try:
    import yaml  # type: ignore
except ImportError:
    raise SystemExit(0)

config = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8")) or {}
modes = config.get("modes") or {}
for name, payload in modes.items():
    desc = ""
    if isinstance(payload, dict):
        desc = str(payload.get("description") or "").strip()
    print(f"{name}\t{desc}")
PYEOF
}

describe_mode() {
  local mode_name="$1"
  python3 - "$AGENT_CONFIG_FILE" "$mode_name" << 'PYEOF'
import sys
from pathlib import Path
try:
    import yaml  # type: ignore
except ImportError:
    raise SystemExit(0)

config = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8")) or {}
mode_name = (sys.argv[2] or "").strip()
mode_cfg = (config.get("modes") or {}).get(mode_name) or {}
if isinstance(mode_cfg, dict):
    print(str(mode_cfg.get("description") or "").strip())
PYEOF
}

evaluate_mode_gate() {
  local active_mode="$1"
  local family="$2"
  local complexity="$3"
  local model_name="$4"
  python3 - "$AGENT_CONFIG_FILE" "$active_mode" "$family" "$complexity" "$model_name" << 'PYEOF'
import sys
from pathlib import Path
try:
    import yaml  # type: ignore
except ImportError:
    print("allow\tactive\t")
    raise SystemExit(0)

config = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8")) or {}
active_mode = (sys.argv[2] or "").strip()
family = (sys.argv[3] or "").strip()
complexity = (sys.argv[4] or "").strip()
model_name = (sys.argv[5] or "").strip()

mode_cfg = (config.get("modes") or {}).get(active_mode) or {}
agents_cfg = mode_cfg.get("agents") if isinstance(mode_cfg, dict) else {}
entry = (agents_cfg or {}).get(family)
status = "active"
min_complexity = ""
min_tier = ""
if isinstance(entry, str):
    status = entry.strip() or "active"
elif isinstance(entry, dict):
    status = str(entry.get("status") or "active").strip() or "active"
    min_complexity = str(entry.get("min_complexity") or "").strip()
    min_tier = str(entry.get("min_tier") or "").strip()

def suggest_agent() -> str:
    order = ["codex", "gemini", "chatgpt", "openclaw", "claude"]
    for key in order:
        if key == family:
            continue
        candidate = (agents_cfg or {}).get(key)
        candidate_status = "active"
        if isinstance(candidate, str):
            candidate_status = candidate.strip() or "active"
        elif isinstance(candidate, dict):
            candidate_status = str(candidate.get("status") or "active").strip() or "active"
        if candidate_status == "active":
            return key
    return ""

if status == "inactive":
    print(f"deny\tinactive\tagent={family} inactive in mode={active_mode}\t{suggest_agent()}")
    raise SystemExit(0)

complexity_order = {"low": 0, "medium": 1, "high": 2, "ultra": 3}
if status == "restricted" and min_complexity:
    cur = complexity_order.get(complexity, -1)
    req = complexity_order.get(min_complexity, -1)
    if cur < req:
        print(f"deny\trestricted\tmode={active_mode} requires complexity>={min_complexity} for {family} (current={complexity})\t{suggest_agent()}")
        raise SystemExit(0)

if status == "restricted" and min_tier:
    models = ((config.get("models") or {}).get(family) or {})
    tier_for_model = ""
    for tier_key, configured_model in models.items():
        if str(configured_model).strip() == model_name:
            tier_for_model = str(tier_key).strip()
            break
    tier_orders = {
        "gemini": {"light": 0, "default": 1, "heavy": 2},
        "chatgpt": {"light": 0, "default": 1, "heavy": 2, "ultra": 3},
        "codex": {"mini": 0, "light": 1, "heavy": 2, "ultra": 3},
        "claude": {"light": 0, "mid": 1, "heavy": 2},
    }
    order = tier_orders.get(family, {})
    cur = order.get(tier_for_model, -1)
    req = order.get(min_tier, -1)
    if cur < req:
        shown = tier_for_model or "unknown"
        print(f"deny\trestricted\tmode={active_mode} requires tier>={min_tier} for {family} (current={shown})\t{suggest_agent()}")
        raise SystemExit(0)

print(f"allow\t{status}\t\t")
PYEOF
}

enforce_mode_gate() {
  local family="$1"
  local complexity="${2:-medium}"
  local model_name="${3:-}"
  local active_mode gate_result gate_decision gate_reason gate_message gate_suggestion
  active_mode="$(get_active_mode)"
  gate_result="$(evaluate_mode_gate "$active_mode" "$family" "$complexity" "$model_name" 2>/dev/null || true)"
  IFS=$'\t' read -r gate_decision gate_reason gate_message gate_suggestion <<< "$gate_result"
  if [ "${gate_decision:-allow}" != "allow" ]; then
    echo "[MODE] Blocked: ${gate_message:-agent blocked by mode=$active_mode}"
    if [ -n "${gate_suggestion:-}" ]; then
      echo "[MODE] Suggestion: use agent=$gate_suggestion"
    fi
    return 1
  fi
  return 0
}

# ============================================================
# Agent Functions (defined before subcommands so --resume can use them)
# ============================================================

# --- Rate limit detection ---
is_rate_limited() {
  local output="$1"
  # Check only last 30 lines to avoid false positives from file contents read by agents
  if echo "$output" | tail -10 | grep -qEi "rate.?limit|429|too.?many.?requests|resource.?exhausted|quota.?exceeded" && ! echo "$output" | tail -5 | grep -qEi "Retrying|success|완료|saved|VAULT"; then
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
  local agent="$1" model="$2" reasoning="${3:-}"
  echo "=== DRY RUN ==="
  echo "Agent:   $agent"
  [ -n "${SELECTED_COMPLEXITY_TIER:-}" ] && echo "Tier:    $SELECTED_COMPLEXITY_TIER"
  echo "Model:   $model"
  [ -n "$reasoning" ] && echo "Reason:  $reasoning"
  echo "Task:    $TASK_NAME"
  echo "Brief:"
  echo "---"
  echo "$TASK"
  echo "---"
  echo "(실제 실행 없음)"
}

fallback_chain_key_for_agent() {
  local agent="$1"
  case "$agent" in
    codex|codex-spark|codex-fallback) echo "code_generation" ;;
    gemini|gemini-pro|gemini-fallback) echo "research" ;;
    chatgpt|chatgpt-mini|chatgpt-light) echo "general" ;;
    *) echo "" ;;
  esac
}

fallback_research_tier_for_complexity() {
  local complexity_tier="${1:-}"
  case "$complexity_tier" in
    light|default|heavy) echo "$complexity_tier" ;;
    low) echo "light" ;;
    medium|high) echo "default" ;;
    ultra) echo "heavy" ;;
    *) echo "default" ;;
  esac
}

fallback_subchain_tier_for_chain() {
  local chain_key="$1"
  local complexity_tier="${2:-}"
  case "$chain_key" in
    research) fallback_research_tier_for_complexity "$complexity_tier" ;;
    *) echo "" ;;
  esac
}

describe_fallback_chain() {
  local chain_key="$1"
  local chain_tier="${2:-}"
  [ -n "$chain_key" ] || return 0
  local active_mode
  active_mode="$(get_active_mode)"

  python3 - "$AGENT_CONFIG_FILE" "$chain_key" "$chain_tier" "$active_mode" << 'PYEOF'
import sys
from pathlib import Path

try:
    import yaml  # type: ignore
except ImportError:
    print("")
    raise SystemExit(0)

config_path = Path(sys.argv[1])
chain_key = sys.argv[2]
chain_tier = str(sys.argv[3]).strip()
active_mode = str(sys.argv[4]).strip()
config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
models = config.get("models") or {}
reasoning = config.get("reasoning") or {}
chain_root = (config.get("fallback") or {}).get(chain_key)
mode_cfg = ((config.get("modes") or {}).get(active_mode) or {}) if active_mode else {}
overrides_root = mode_cfg.get("fallback_overrides") if isinstance(mode_cfg, dict) else {}
chain_override = (overrides_root or {}).get(chain_key)

def agent_family(agent_name: str) -> str:
    if agent_name.startswith("codex"):
        return "codex"
    if agent_name.startswith("chatgpt"):
        return "chatgpt"
    if agent_name.startswith("gemini"):
        return "gemini"
    if agent_name.startswith("claude"):
        return "claude"
    return agent_name

def format_chain(chain):
    if not isinstance(chain, list):
        return ""
    parts = []
    for step in chain:
        if not isinstance(step, dict):
            continue
        if "action" in step:
            parts.append(str(step["action"]).strip())
            continue

        agent = str(step.get("agent", "")).strip()
        model_ref = str(step.get("model_key", "")).strip()
        family = agent_family(agent)
        model_key = model_ref
        if "." in model_ref:
            family, model_key = model_ref.split(".", 1)

        model = str(((models.get(family) or {}).get(model_key) or "")).strip()
        effort = str(((reasoning.get(family) or {}).get(model_key) or "")).strip()

        label = f"{agent}:{model or model_key or 'unresolved'}"
        if effort and effort != "auto":
            label += f"[{effort}]"
        parts.append(label)
    return " -> ".join(parts)

if isinstance(chain_override, list):
    print(format_chain(chain_override))
    raise SystemExit(0)

if isinstance(chain_override, dict):
    if chain_tier:
        if chain_tier in chain_override:
            print(format_chain(chain_override.get(chain_tier) or []))
            raise SystemExit(0)
    else:
        ordered_tiers = ["light", "default", "heavy"]
        seen = set()
        parts = []
        for tier_name in ordered_tiers + [k for k in chain_override.keys() if k not in ordered_tiers]:
            if tier_name in seen:
                continue
            seen.add(tier_name)
            chain_desc = format_chain(chain_override.get(tier_name) or [])
            if chain_desc:
                parts.append(f"{tier_name}: {chain_desc}")
        if parts:
            print(" || ".join(parts))
            raise SystemExit(0)

if not isinstance(chain_root, dict):
    print("")
    raise SystemExit(0)

if chain_tier:
    chosen_tier = chain_tier if chain_tier in chain_root else "default"
    print(format_chain(chain_root.get(chosen_tier) or []))
    raise SystemExit(0)

ordered_tiers = ["light", "default", "heavy"]
seen = set()
parts = []
for tier_name in ordered_tiers + [k for k in chain_root.keys() if k not in ordered_tiers]:
    if tier_name in seen:
        continue
    seen.add(tier_name)
    chain_desc = format_chain(chain_root.get(tier_name) or [])
    if chain_desc:
        parts.append(f"{tier_name}: {chain_desc}")

print(" || ".join(parts))
PYEOF
}

get_fallback_chain_steps() {
  local chain_key="$1"
  local chain_tier="${2:-}"
  [ -n "$chain_key" ] || return 0
  local active_mode
  active_mode="$(get_active_mode)"

  python3 - "$AGENT_CONFIG_FILE" "$chain_key" "$chain_tier" "$active_mode" << 'PYEOF'
import sys
from pathlib import Path

try:
    import yaml  # type: ignore
except ImportError:
    raise SystemExit(0)

config_path = Path(sys.argv[1])
chain_key = sys.argv[2]
chain_tier = str(sys.argv[3]).strip()
active_mode = str(sys.argv[4]).strip()
config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
models = config.get("models") or {}
reasoning = config.get("reasoning") or {}
chain_root = (config.get("fallback") or {}).get(chain_key)
mode_cfg = ((config.get("modes") or {}).get(active_mode) or {}) if active_mode else {}
overrides_root = mode_cfg.get("fallback_overrides") if isinstance(mode_cfg, dict) else {}
chain_override = (overrides_root or {}).get(chain_key)

def agent_family(agent_name: str) -> str:
    if agent_name.startswith("codex"):
        return "codex"
    if agent_name.startswith("chatgpt"):
        return "chatgpt"
    if agent_name.startswith("gemini"):
        return "gemini"
    if agent_name.startswith("claude"):
        return "claude"
    return agent_name

if isinstance(chain_override, list):
    chain = chain_override
elif isinstance(chain_override, dict) and chain_tier and chain_tier in chain_override:
    chain = chain_override.get(chain_tier) or []
elif isinstance(chain_root, list):
    chain = chain_root
elif isinstance(chain_root, dict):
    chosen_tier = chain_tier if chain_tier in chain_root else "default"
    chain = chain_root.get(chosen_tier) or []
else:
    chain = []

for step in chain:
    if not isinstance(step, dict):
        continue
    if "action" in step:
        print(f"action\t{str(step['action']).strip()}")
        continue

    agent = str(step.get("agent", "")).strip()
    model_ref = str(step.get("model_key", "")).strip()
    family = agent_family(agent)
    model_key = model_ref
    if "." in model_ref:
        family, model_key = model_ref.split(".", 1)

    model = str(((models.get(family) or {}).get(model_key) or "")).strip()
    effort = str(((reasoning.get(family) or {}).get(model_key) or "")).strip()
    print(f"agent\t{agent}\t{family}\t{model}\t{effort}")
PYEOF
}

# --- Complexity tier + model selector (agent_config.yaml) ---
# Heuristic-only classifier: no external NLP, just stable keyword/count rules.
# Prints tab-separated values: <tier>\t<model>\t<reasoning>\t<family>\t<source>
# Map task text → Codex subagent name
# Returns empty string if no match (Codex handles it alone)
# resolve_subagent_hint <task_text> [tier]
# tier: low | medium | high | ultra (default: medium)
# Ultra-tier subagents only fire on high/ultra to avoid model cost mismatch
resolve_subagent_hint() {
  local task="$1"
  local tier="${2:-medium}"
  local t
  t=$(echo "$task" | tr '[:upper:]' '[:lower:]')

  # --- Exclude research/analysis-only patterns (false positive guard) ---
  # If task is about researching/explaining/summarizing, skip code subagents
  if echo "$t" | grep -qE "조사|찾아줘|검색|리서치|요약|설명해|분석해줘$|알려줘$"; then
    echo ""; return
  fi

  # --- Medium/Light subagents (always eligible) ---

  # MCP (more specific than CLI — check first)
  if echo "$t" | grep -qE "mcp|model context protocol"; then
    echo "mcp-developer"; return
  fi
  # Python — must involve coding/writing/fixing, not just mentioning python
  if echo "$t" | grep -qE "\.py|pytest|django|flask|fastapi|pandas|numpy" || \
     (echo "$t" | grep -qE "python" && echo "$t" | grep -qE "작성|구현|수정|고쳐|만들어|짜줘|fix|write|implement"); then
    echo "python-pro"; return
  fi
  # Shell/CLI — must involve scripting
  if echo "$t" | grep -qE "\.sh|bash.*(작성|수정|고쳐)|shell.*(script|작성)|(스크립트|쉘).*(작성|수정|만들)"; then
    echo "cli-developer"; return
  fi
  # Code review — explicit review request
  if echo "$t" | grep -qE "코드.?(리뷰|검토)|code.?review|pr.?review"; then
    echo "reviewer"; return
  fi

  # --- Ultra-tier subagents (high/ultra only) ---
  if [[ "$tier" == "high" || "$tier" == "ultra" ]]; then
    if echo "$t" | grep -qE "multi.?agent|멀티.?에이전트|여러.에이전트|에이전트.협업"; then
      echo "multi-agent-coordinator"; return
    fi
    if echo "$t" | grep -qE "workflow|워크플로우|파이프라인.설계|자동화.플로우"; then
      echo "workflow-orchestrator"; return
    fi
    if echo "$t" | grep -qE "task.?distribut|태스크.분배|작업.분배|역할.분담"; then
      echo "task-distributor"; return
    fi
  fi

  echo ""
}

# inject_ua_context <task_text> <tier> <work_dir>
# Extracts relevant codebase context from Understand-Anything knowledge graph.
# Returns context markdown on stdout, or empty if KG not found / tier too low.
inject_ua_context() {
  local task="$1"
  local tier="${2:-medium}"
  local work_dir="${3:-}"

  # Gate: skip for low tier
  [[ "$tier" == "low" ]] && return

  # Gate: need work_dir
  [ -z "$work_dir" ] && return

  # Gate: KG must exist
  local kg_file="$work_dir/.understand-anything/knowledge-graph.json"
  [ -f "$kg_file" ] || return

  # Gate: check if UA is enabled in config
  local ua_enabled
  ua_enabled=$(python3 -c "
import yaml, sys
try:
    c = yaml.safe_load(open('$AGENT_CONFIG_FILE'))
    print(c.get('ua',{}).get('enabled', True))
except: print(True)
" 2>/dev/null || echo "True")
  [[ "$ua_enabled" == "False" ]] && return

  # Resolve max_tokens from config
  local max_tokens=2000
  if [[ "$tier" == "high" ]]; then max_tokens=4000
  elif [[ "$tier" == "ultra" ]]; then max_tokens=6000
  fi

  # Stale KG warning (30+ days)
  local kg_age_days
  kg_age_days=$(python3 -c "
import os, time
mtime = os.path.getmtime('$kg_file')
print(int((time.time() - mtime) / 86400))
" 2>/dev/null || echo "0")
  if [ "$kg_age_days" -gt 30 ] 2>/dev/null; then
    echo "[UA] Warning: Knowledge graph is ${kg_age_days} days old" >&2
  fi

  # Extract context
  local context
  context=$(python3 "$SCRIPT_DIR/ua_context.py" "$work_dir" "$task" --tier "$tier" --max-tokens "$max_tokens" 2>/dev/null || true)

  [ -n "$context" ] && echo "$context"
}

resolve_dispatch_profile() {
  local agent="$1"
  local task_text="$2"
  python3 - "$AGENT_CONFIG_FILE" "$agent" "$task_text" << 'PYEOF'
import sys
import re
from pathlib import Path

config_path = sys.argv[1]
agent = (sys.argv[2] or "").strip().lower()
task_text = sys.argv[3] if len(sys.argv) > 3 else ""

BUILTIN_MODELS = {
    "codex": {
        "ultra": "gpt-5.4",
        "heavy": "gpt-5.3-codex",
        "light": "gpt-5.3-codex-spark",
        "mini": "gpt-5-codex-mini",
    },
    "chatgpt": {
        "heavy": "gpt-5.2",
        "default": "gpt-5.1",
        "light": "gpt-5",
    },
    "gemini": {
        "heavy": "gemini-2.5-pro",
        "default": "gemini-2.5-flash",
        "light": "gemini-2.5-flash-lite",
    },
    "claude": {
        "heavy": "opus",
        "mid": "sonnet",
        "light": "haiku",
    },
}

BUILTIN_REASONING = {
    "codex": {"ultra": "xhigh", "heavy": "xhigh", "light": "high", "mini": "medium"},
    "chatgpt": {"ultra": "xhigh", "heavy": "high", "default": "medium", "light": "low"},
    "gemini": {"heavy": "auto", "default": "auto", "light": "auto"},
    "claude": {
        "opus": "high",
        "sonnet": "medium",
        "haiku": "low",
        "sonnet_high": "high",
        "haiku_medium": "medium",
    },
}

LEGACY_DEFAULT_KEYS = {
    "codex": "heavy",
    "chatgpt": "default",
    "gemini": "default",
    "claude": "mid",
}

MODEL_KEY_ORDER = {
    "codex": ["ultra", "heavy", "light", "mini"],
    "chatgpt": ["ultra", "heavy", "default", "light"],
    "gemini": ["heavy", "default", "light"],
    "claude": ["heavy", "mid", "light"],
}

ALIAS_OVERRIDES = {
    "codex-spark": ("codex", "light"),
    "gemini-pro": ("gemini", "heavy"),
    "chatgpt-mini": ("chatgpt", "default"),
    "chatgpt-light": ("chatgpt", "light"),
}

EFFORT_ALIASES = {
    "": "",
    "auto": "auto",
    "low": "low",
    "medium": "medium",
    "med": "medium",
    "high": "high",
    "xhigh": "xhigh",
    "extra-high": "xhigh",
    "extra high": "xhigh",
}

try:
    import yaml  # type: ignore
except Exception:
    yaml = None

config = {}
if yaml is not None:
    try:
        config = yaml.safe_load(Path(config_path).read_text(encoding="utf-8")) or {}
    except Exception:
        config = {}

models = config.get("models") or BUILTIN_MODELS
reasoning = config.get("reasoning") or BUILTIN_REASONING
complexity = config.get("complexity_tiers") or {}

def ordered_unique(values):
    seen = set()
    result = []
    for value in values:
        value = str(value or "").strip()
        if not value or value in seen:
            continue
        seen.add(value)
        result.append(value)
    return result

def first_non_empty(values):
    for value in values:
        value = str(value or "").strip()
        if value:
            return value
    return ""

def normalize_effort(value):
    raw = str(value or "").strip().lower().replace("_", " ").replace("-", " ")
    return EFFORT_ALIASES.get(raw, str(value or "").strip())

def infer_tier(task: str) -> str:
    text = task or ""
    lower = text.lower()

    forced = re.search(r"(?:complexity[_ -]?tier|tier)\s*[:=]\s*(low|medium|high|ultra)\b", lower)
    if forced:
        return forced.group(1)

    file_range_pattern = r"(\d+)\s*(?:to|[-~])\s*(\d+)\s*(?:files?|개\s*파일|파일|문서)"
    file_ranges = [(min(int(a), int(b)), max(int(a), int(b))) for a, b in re.findall(file_range_pattern, lower)]
    lower_no_file_ranges = re.sub(file_range_pattern, " ", lower)
    single_files = [int(x) for x in re.findall(r"(\d+)\s*\+?\s*(?:files?|개\s*파일|파일|문서)", lower_no_file_ranges)]
    less_than_files = [max(int(x) - 1, 0) for x in re.findall(r"(?:<|under|less than)\s*(\d+)\s*(?:files?|개\s*파일|파일|문서)", lower)]
    file_count = max(single_files + less_than_files) if (single_files or less_than_files) else None
    file_floor_candidates = [low for low, _ in file_ranges] + single_files
    file_ceiling_candidates = [high for _, high in file_ranges] + single_files + less_than_files
    file_floor = max(file_floor_candidates) if file_floor_candidates else None
    file_ceiling = min(file_ceiling_candidates) if file_ceiling_candidates else None

    line_range_pattern = r"(\d+)\s*(?:to|[-~])\s*(\d+)\s*(?:lines?|loc|줄)"
    line_ranges = [(min(int(a), int(b)), max(int(a), int(b))) for a, b in re.findall(line_range_pattern, lower)]
    lower_no_line_ranges = re.sub(line_range_pattern, " ", lower)
    single_lines = [int(x) for x in re.findall(r"(?<![<≤])(\d+)\s*\+?\s*(?:lines?|loc|줄)", lower_no_line_ranges)]
    less_than_lines = [max(int(x) - 1, 0) for x in re.findall(r"(?:<|under|less than)\s*(\d+)\s*(?:lines?|loc|줄)", lower)]
    korean_less_than_lines = [max(int(x) - 1, 0) for x in re.findall(r"(\d+)\s*(?:lines?|loc|줄)\s*미만", lower)]
    line_count = max(single_lines + less_than_lines + korean_less_than_lines) if (single_lines or less_than_lines or korean_less_than_lines) else None
    line_floor_candidates = [low for low, _ in line_ranges] + single_lines
    line_ceiling_candidates = [high for _, high in line_ranges] + single_lines + less_than_lines + korean_less_than_lines
    line_floor = max(line_floor_candidates) if line_floor_candidates else None
    line_ceiling = min(line_ceiling_candidates) if line_ceiling_candidates else None

    ultra_kw = [
        "full codebase", "entire codebase", "whole codebase", "architecture",
        "architectural", "system design", "design pattern", "novel design",
        "multi-system orchestration", "repo-wide", "cross-repository",
        "전체 분석", "전체 코드베이스", "전사 분석", "아키텍처", "신규 설계", "설계 패턴", "멀티 시스템",
        "복합 교차분석", "코드베이스 전반", "전면 재설계"
    ]
    high_kw = [
        "complex bug", "unclear root cause", "non-trivial refactor", "cross-system",
        "root cause", "deep analysis", "investigation", "multi-step fix",
        "복잡한 버그", "리팩터", "리팩토", "원인 불명", "대규모 수정",
        "깊은 분석", "비자명", "교차 분석", "원인 분석", "문제 추적"
    ]
    medium_kw = [
        "new feature", "feature", "standard coding", "implementation", "integrate",
        "새 기능", "기능 추가", "기능추가", "표준 코딩", "일반 구현", "리서치"
    ]
    low_kw = [
        "simple", "simple edit", "small fix", "quick fix", "typo", "lookup", "read-only",
        "단순 수정", "문구 수정", "조회", "간단한 조사", "소규모 수정", "경미한 수정"
    ]

    has_ultra_kw = any(k in lower for k in ultra_kw)
    has_high_kw = any(k in lower for k in high_kw)
    has_medium_kw = any(k in lower for k in medium_kw)
    has_low_kw = any(k in lower for k in low_kw)

    if has_ultra_kw:
        return "ultra"

    # Rule order matches requested precedence:
    # ultra (codebase/architecture) > high (5+ files or complex bug) >
    # low (1-3 files + <10 lines + simple lookup/edit) > medium (default).
    if has_high_kw:
        return "high"
    if (file_floor is not None and file_floor >= 5) or (file_count is not None and file_count >= 5):
        return "high"
    if (line_floor is not None and line_floor >= 80) or (line_count is not None and line_count >= 80):
        return "high"

    low_file_band = file_ceiling is not None and file_ceiling <= 3
    low_line_band = line_ceiling is not None and line_ceiling < 10
    if low_file_band and low_line_band and (has_low_kw or not has_medium_kw):
        return "low"

    if has_medium_kw:
        return "medium"
    if file_floor is not None and 3 <= file_floor <= 5:
        return "medium"
    if file_count is not None and 3 <= file_count <= 5:
        return "medium"

    if low_file_band and (line_ceiling is None or line_ceiling < 10):
        return "low"

    return "medium"

def infer_role(task: str) -> str:
    """Infer task role from text for checklist injection."""
    lower = (task or "").lower()
    # Order matters: more specific roles first, generic ones last
    security_kw = [
        "security", "보안", "취약점", "vulnerability", "auth", "인증", "권한",
        "injection", "xss", "csrf", "secret", "credential", "penetration",
        "보안 감사", "보안 점검", "보안 리뷰",
    ]
    testing_kw = [
        "test", "테스트", "테스팅", "unit test", "e2e test", "integration test",
        "regression", "coverage", "커버리지", "테스트 작성", "테스트 추가",
    ]
    performance_kw = [
        "performance", "성능", "병목", "bottleneck", "latency", "throughput",
        "최적화", "optimization", "slow", "느린", "속도", "profil",
    ]
    review_kw = [
        "review", "리뷰", "코드 리뷰", "code review", "pr review",
        "감사", "audit", "검토", "점검", "코드 점검", "코드 검토",
    ]
    refactor_kw = [
        "refactor", "리팩토링", "리팩터", "리팩토", "restructure", "구조 개선",
        "코드 정리", "모듈화", "중복 제거", "dedup",
    ]
    doc_kw = [
        "document", "문서", "입문서", "가이드", "readme", "설명서", "매뉴얼",
        "documentation", "docs", "튜토리얼", "howto",
    ]
    trend_kw = [
        "trend", "트렌드", "동향", "adoption", "채택", "hype", "emerging",
        "신기술", "기술 동향", "시장 동향",
    ]
    research_kw = [
        "research", "리서치", "조사", "investigate", "분석", "analysis",
        "비교", "compare", "평가", "evaluation", "검토 보고",
        "알아봐", "알아보", "찾아봐", "찾아보", "파악",
    ]
    data_kw = [
        "data", "데이터", "지표", "metric", "통계", "statistics",
        "수치", "정량", "quantitative", "dataset", "매출", "비용",
    ]
    roles = [
        (security_kw, "security"),
        (testing_kw, "testing"),
        (performance_kw, "performance"),
        (review_kw, "reviewer"),
        (refactor_kw, "refactoring"),
        (trend_kw, "trend"),
        (data_kw, "data"),
        (research_kw, "research"),
        (doc_kw, "documentation"),  # generic — last (가이드/문서 are common words)
    ]
    # Score each role by number of keyword hits; highest wins.
    # Tie-break by list order (earlier = higher priority).
    best_role = ""
    best_score = 0
    for keywords, role_name in roles:
        score = sum(1 for k in keywords if k in lower)
        if score > best_score:
            best_score = score
            best_role = role_name
    return best_role

def agent_family(agent_name: str) -> str:
    if agent_name.startswith("codex"):
        return "codex"
    if agent_name.startswith("chatgpt"):
        return "chatgpt"
    if agent_name.startswith("gemini"):
        return "gemini"
    if agent_name.startswith("claude"):
        return "claude"
    return agent_name

def model_key_candidates(family: str, requested_key: str):
    requested_key = str(requested_key or "").strip()
    order = MODEL_KEY_ORDER.get(family, [])
    legacy_key = LEGACY_DEFAULT_KEYS.get(family, "")
    if requested_key and requested_key in order:
        idx = order.index(requested_key)
        candidates = [requested_key] + order[idx + 1 :] + [legacy_key] + order[:idx]
    else:
        candidates = [requested_key, legacy_key] + order
    return ordered_unique(candidates)

def resolve_standard_family(family: str, requested_key: str, requested_effort: str):
    family_models = {str(k).strip(): str(v).strip() for k, v in (models.get(family) or {}).items()}
    family_reasoning = reasoning.get(family) or {}
    resolved_key = ""
    model_name = ""
    for candidate in model_key_candidates(family, requested_key):
        model_name = family_models.get(candidate, "")
        if model_name:
            resolved_key = candidate
            break
    effort = first_non_empty([
        normalize_effort(requested_effort),
        normalize_effort(family_reasoning.get(resolved_key, "")),
        normalize_effort(family_reasoning.get(requested_key, "")),
        normalize_effort(family_reasoning.get(LEGACY_DEFAULT_KEYS.get(family, ""), "")),
    ])
    return model_name, effort, resolved_key

def resolve_claude(requested_model: str, requested_effort: str):
    family_models = {str(k).strip(): str(v).strip() for k, v in (models.get("claude") or {}).items()}
    family_reasoning = reasoning.get("claude") or {}
    by_value = {value: key for key, value in family_models.items()}
    requested_model = str(requested_model or "").strip()
    model_name = ""
    model_key = ""
    if requested_model in family_models:
        model_key = requested_model
        model_name = family_models.get(model_key, "")
    elif requested_model in by_value:
        model_name = requested_model
        model_key = by_value[requested_model]
    else:
        model_key = LEGACY_DEFAULT_KEYS.get("claude", "mid")
        model_name = family_models.get(model_key, "")

    effort = normalize_effort(requested_effort)
    if not effort:
        effort = first_non_empty([
            normalize_effort(family_reasoning.get(model_name, "")),
            normalize_effort(family_reasoning.get(model_key, "")),
        ])

    return model_name, effort, model_key

def resolve_from_complexity(family: str, tier_name: str):
    tier_map = complexity.get(tier_name) or {}
    agent_map = tier_map.get(family) or {}
    if family == "claude":
        requested_model = agent_map.get("model", "") or agent_map.get("tier", "")
        requested_effort = agent_map.get("effort", "") or agent_map.get("reasoning", "")
        model_name, effort, resolved_key = resolve_claude(requested_model, requested_effort)
        requested_key = str(requested_model or "").strip()
    else:
        requested_key = str(agent_map.get("tier", "") or agent_map.get("model", "")).strip()
        requested_effort = agent_map.get("reasoning", "") or agent_map.get("effort", "")
        model_name, effort, resolved_key = resolve_standard_family(family, requested_key, requested_effort)

    source = "complexity"
    if requested_key and resolved_key and requested_key != resolved_key:
        source = "complexity-fallback"
    return model_name, effort, source

def resolve_legacy(agent_name: str):
    family = agent_family(agent_name)
    if agent_name in ALIAS_OVERRIDES:
        family, requested_key = ALIAS_OVERRIDES[agent_name]
        model_name, effort, _ = resolve_standard_family(family, requested_key, "")
        return family, model_name, effort or normalize_effort((reasoning.get(family) or {}).get(requested_key, "")), "legacy-alias"

    if family == "claude":
        default_key = LEGACY_DEFAULT_KEYS.get("claude", "mid")
        model_name, effort, _ = resolve_claude(default_key, "")
        return family, model_name, effort, "legacy-default"

    default_key = LEGACY_DEFAULT_KEYS.get(family, "")
    model_name, effort, _ = resolve_standard_family(family, default_key, "")
    return family, model_name, effort, "legacy-default"

family = agent_family(agent)
tier = infer_tier(task_text)
role = infer_role(task_text)

if agent in ALIAS_OVERRIDES:
    family, model_name, effort, source = resolve_legacy(agent)
    print(f"{tier}\t{model_name}\t{effort}\t{family}\t{source}\t{role}", end="")
    sys.exit(0)

model_name, effort, source = resolve_from_complexity(family, tier)
if not model_name:
    family, model_name, effort, source = resolve_legacy(agent)

print(f"{tier}\t{model_name}\t{effort}\t{family}\t{source}\t{role}", end="")
PYEOF
}

select_dispatch_profile_legacy() {
  local agent="$1"
  case "$agent" in
    codex)
      SELECTED_FAMILY="codex"
      SELECTED_MODEL="gpt-5.3-codex"
      SELECTED_REASONING="xhigh"
      ;;
    codex-spark)
      SELECTED_FAMILY="codex"
      SELECTED_MODEL="gpt-5.3-codex-spark"
      SELECTED_REASONING="high"
      ;;
    gemini)
      SELECTED_FAMILY="gemini"
      SELECTED_MODEL="gemini-2.5-flash"
      SELECTED_REASONING="auto"
      ;;
    gemini-pro)
      SELECTED_FAMILY="gemini"
      SELECTED_MODEL="gemini-2.5-pro"
      SELECTED_REASONING="auto"
      ;;
    chatgpt)
      SELECTED_FAMILY="chatgpt"
      SELECTED_MODEL="gpt-5.2"
      SELECTED_REASONING="high"
      ;;
    chatgpt-mini)
      SELECTED_FAMILY="chatgpt"
      SELECTED_MODEL="gpt-5.1"
      SELECTED_REASONING="medium"
      ;;
    chatgpt-light)
      SELECTED_FAMILY="chatgpt"
      SELECTED_MODEL="gpt-5"
      SELECTED_REASONING="low"
      ;;
    *)
      SELECTED_FAMILY="$agent"
      SELECTED_MODEL=""
      SELECTED_REASONING=""
      ;;
  esac

  [ -n "${SELECTED_COMPLEXITY_TIER:-}" ] || SELECTED_COMPLEXITY_TIER="legacy"
  SELECTED_PROFILE_SOURCE="legacy-shell-default"
}

select_dispatch_profile() {
  local agent="$1"
  local resolved=""
  resolved="$(resolve_dispatch_profile "$agent" "$TASK" 2>/dev/null || true)"

  SELECTED_COMPLEXITY_TIER=""
  SELECTED_MODEL=""
  SELECTED_REASONING=""
  SELECTED_FAMILY=""
  SELECTED_PROFILE_SOURCE=""
  SELECTED_ROLE=""
  IFS=$'\t' read -r SELECTED_COMPLEXITY_TIER SELECTED_MODEL SELECTED_REASONING SELECTED_FAMILY SELECTED_PROFILE_SOURCE SELECTED_ROLE <<< "$resolved"

  if [ -z "${SELECTED_MODEL:-}" ] || [ -z "${SELECTED_FAMILY:-}" ]; then
    echo "[WARN] Complexity routing unavailable for agent=$agent. Falling back to legacy defaults."
    select_dispatch_profile_legacy "$agent"
  fi

  if [ -z "${SELECTED_MODEL:-}" ]; then
    echo "[ERROR] No configured model for agent=$agent tier=${SELECTED_COMPLEXITY_TIER:-unknown}" >&2
    return 1
  fi

  if ! enforce_mode_gate "${SELECTED_FAMILY:-}" "${SELECTED_COMPLEXITY_TIER:-}" "${SELECTED_MODEL:-}"; then
    return 1
  fi

  local active_mode
  active_mode="$(get_active_mode)"
  echo "[ROUTER] mode=${active_mode:-unknown} tier=${SELECTED_COMPLEXITY_TIER:-unknown} agent=$agent family=${SELECTED_FAMILY:-unknown} model=${SELECTED_MODEL:-unknown} reasoning=${SELECTED_REASONING:-auto} role=${SELECTED_ROLE:-none}"
  if [ -n "${SELECTED_PROFILE_SOURCE:-}" ] && [ "$SELECTED_PROFILE_SOURCE" != "complexity" ]; then
    echo "[ROUTER] profile_source=${SELECTED_PROFILE_SOURCE}"
  fi
  local fallback_key fallback_desc
  local fallback_tier=""
  fallback_key="$(fallback_chain_key_for_agent "$agent")"
  fallback_tier="$(fallback_subchain_tier_for_chain "$fallback_key" "${SELECTED_COMPLEXITY_TIER:-}")"
  fallback_desc="$(describe_fallback_chain "$fallback_key" "$fallback_tier" 2>/dev/null || true)"
  if [ -n "$fallback_key" ] && [ -n "$fallback_desc" ]; then
    if [ -n "$fallback_tier" ]; then
      echo "[ROUTER] fallback=${fallback_key}(${fallback_tier}): ${fallback_desc}"
    else
      echo "[ROUTER] fallback=${fallback_key}: ${fallback_desc}"
    fi
  fi
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

  python3 - "$AGENT_CONFIG_FILE" "$target" "$output_json" << 'PYEOF'
import json
import sys
from pathlib import Path

try:
    import yaml  # type: ignore
except ImportError as exc:
    print(f"[ERROR] PyYAML is required for schema output: {exc}", file=sys.stderr)
    raise SystemExit(1)

config = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8")) or {}
target = sys.argv[2].strip()
output_json = sys.argv[3].strip().lower() == "true"
models = config.get("models") or {}

AGENTS = {
    "codex": {
        "family": "codex",
        "tier": "heavy",
        "models_mode": "family",
        "use_for": ["Code generation, refactoring, test loops", "4+ files or 50+ lines of code"],
        "quota": "use first for code tasks",
        "fallback": "code_generation",
    },
    "codex-spark": {
        "family": "codex",
        "tier": "light",
        "models_mode": "single",
        "use_for": ["Quick edits, small patches, fast iterations"],
        "quota": "high",
        "fallback": "code_generation",
    },
    "gemini": {
        "family": "gemini",
        "tier": "default",
        "models_mode": "single",
        "use_for": ["Research, summarization, lightweight analysis"],
        "quota": "config-driven",
        "fallback": "research",
    },
    "gemini-pro": {
        "family": "gemini",
        "tier": "heavy",
        "models_mode": "single",
        "use_for": ["Deep analysis, complex reasoning tasks"],
        "quota": "config-driven",
        "fallback": "research",
    },
    "chatgpt": {
        "family": "chatgpt",
        "tier": "heavy",
        "models_mode": "single",
        "use_for": ["Writing, summarization, general non-coding tasks"],
        "quota": "config-driven",
        "fallback": "general",
    },
    "chatgpt-mini": {
        "family": "chatgpt",
        "tier": "default",
        "models_mode": "single",
        "use_for": ["Budget general tasks, translation, processing"],
        "quota": "config-driven",
        "fallback": "general",
    },
    "chatgpt-light": {
        "family": "chatgpt",
        "tier": "light",
        "models_mode": "single",
        "use_for": ["Simple transforms, bulk lightweight tasks"],
        "quota": "config-driven",
        "fallback": "general",
    },
}

def ordered_unique(values):
    seen = set()
    result = []
    for value in values:
        if not value or value in seen:
            continue
        seen.add(value)
        result.append(value)
    return result

def build_schema(name: str):
    if name not in AGENTS:
        return None
    spec = AGENTS[name]
    family = spec["family"]
    family_models = models.get(family) or {}
    default_model = str(family_models.get(spec["tier"], "") or "")
    if spec["models_mode"] == "family":
        model_list = ordered_unique(str(v or "") for v in family_models.values())
    else:
        model_list = [default_model] if default_model else []
    return {
        "name": name,
        "models": model_list,
        "default_model": default_model,
        "use_for": spec["use_for"],
        "flags": {
            "--dry-run": "Validate without executing",
            "--json <JSON>": "Structured task input (goal, scope, constraints, output)",
        },
        "input": {
            "task": "string (required) — task description or @filepath or --json",
            "task_name": "string (optional, default: unnamed)",
        },
        "quota": spec["quota"],
        "fallback": f"{spec['fallback']} (config-driven)",
    }

if output_json:
    if target:
        schema = build_schema(target)
        if schema is None:
            print(f"[ERROR] Unknown agent for schema: {target}", file=sys.stderr)
            raise SystemExit(1)
        print(json.dumps(schema, ensure_ascii=False))
        raise SystemExit(0)

    payload = {
        "agents": [build_schema(name) for name in AGENTS],
        "dispatch": {
            "usage": 'orchestrate.sh <agent> "<task>" <task-name> [--dry-run]',
            "flags": {
                "--dry-run": "validate without executing",
                "--save": "save result to vault",
                "--resume": "re-attach to existing task by name",
            },
        },
        "system": {
            "--boot": {"description": "scan queue on session start, re-dispatch stale tasks", "returns": "pending count"},
            "--status": {"description": "show all queue entries", "flags": {"--json": "machine-readable JSON output"}, "returns": "table or JSON"},
            "--resume": {"description": "re-dispatch oldest pending/queued task", "returns": "dispatch result"},
            "--complete": {"usage": "--complete <ID> <summary>", "description": "manually mark task as completed"},
            "--cost": {"description": "today's usage per model + limits", "returns": "cost table"},
            "--clean": {"usage": "--clean [--dry]", "description": "archive completed queue entries"},
            "--chain": {"usage": '--chain "question" agent1 [agent2...] [task-name]', "description": "pipe output of one agent to next"},
            "run": {"usage": "run <blueprint_file> [--var key=value ...]", "description": "execute YAML blueprint pipeline"},
        },
        "queue": {
            "location": "queue/T###_<name>/",
            "files": {
                "meta.json": "dispatch status, retry count, timestamps",
                "brief.md": "task spec (goal, scope, context budget, stop triggers)",
                "progress.md": "phase checkpoints, notes, resume point",
                "result.md": "agent output",
            },
            "statuses": ["pending", "dispatched", "queued", "completed"],
        },
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    raise SystemExit(0)

if not target:
    print("=== Agent Schema ===\n")
    for name in AGENTS:
        print(f"- {name}")
    print("\nUsage:")
    print("  orchestrate.sh schema")
    print("  orchestrate.sh schema codex")
    print("  orchestrate.sh schema gemini")
    print("  orchestrate.sh schema --json")
    print("  orchestrate.sh run blueprints/slides.yaml --var topic=커피")
    raise SystemExit(0)

schema = build_schema(target)
if schema is None:
    print(f"[ERROR] Unknown agent for schema: {target}", file=sys.stderr)
    raise SystemExit(1)

print(f"=== Agent Schema: {schema['name']} ===\n")
print(f"name:        {schema['name']}")
print("models:")
for model in schema["models"]:
    print(f"  - {model}")
print("use_for:")
for item in schema["use_for"]:
    print(f"  - {item}")
print("flags:")
print("  --dry-run     : Validate without executing")
print("  --json <JSON> : Structured task input (goal, scope, constraints, output)")
print("input:")
print("  task:         string (required) — task description or @filepath or --json")
print("  task-name:    string (optional, default: unnamed)")
print(f"quota:          {schema['quota']}")
print(f"fallback:       {schema['fallback']}")
print("\nexamples:")
print(f"  orchestrate.sh {schema['name']} \"task\" task-name")
print(f"  orchestrate.sh {schema['name']} @brief.md task-name")
print(f"  orchestrate.sh {schema['name']} --json '{{\"goal\":\"...\",\"scope\":\"...\"}}' task-name")
PYEOF
  exit $?
}

# --- Run Codex ---
run_codex() {
  local model="${1:-}"
  local reasoning="${2:-}"
  local log_file="$LOG_DIR/codex_${TASK_NAME}_${TIMESTAMP}.json"

  if [ -z "$model" ]; then
    echo "[ERROR] Missing Codex model for task: $TASK_NAME" >&2
    return 1
  fi

  if [ "${DRY_RUN:-false}" = "true" ]; then
    print_dry_run "$AGENT" "$model" "$reasoning"
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

  # Auto-append role checklist if role was inferred
  local task_with_checklist="$TASK"
  if [ -n "${SELECTED_ROLE:-}" ]; then
    local checklist_file="$SCRIPT_DIR/../configs/checklists/${SELECTED_ROLE}.md"
    if [ -f "$checklist_file" ]; then
      task_with_checklist="${TASK}

$(cat "$checklist_file")"
      echo "[CHECKLIST] Appended role checklist: ${SELECTED_ROLE}"
    fi
  fi

  # Inject subagent hint if applicable
  local subagent_hint
  subagent_hint=$(resolve_subagent_hint "$task_with_checklist" "${SELECTED_COMPLEXITY_TIER:-medium}")
  if [ -n "$subagent_hint" ]; then
    task_with_checklist="[Subagent: use the '${subagent_hint}' subagent for this task]

${task_with_checklist}"
    echo "[SUBAGENT] Hint injected: $subagent_hint"
  fi

  # Inject UA codebase context if available
  local ua_context
  ua_context=$(inject_ua_context "$task_with_checklist" "${SELECTED_COMPLEXITY_TIER:-medium}" "${work_dir:-$(pwd)}")
  if [ -n "$ua_context" ]; then
    task_with_checklist="${ua_context}

${task_with_checklist}"
    echo "[UA] Codebase context injected (tier: ${SELECTED_COMPLEXITY_TIER:-medium})"
  fi

  # Build codex command args
  local codex_args=(
    exec
    --dangerously-bypass-approvals-and-sandbox
    --skip-git-repo-check
    -m "$model"
    --json
  )
  [ -n "$reasoning" ] && codex_args+=(-c "model_reasoning_effort=$reasoning")
  [ -n "$work_dir" ] && codex_args+=(-C "$work_dir")

  # Write directly to file to avoid shell variable truncation
  codex "${codex_args[@]}" "$task_with_checklist" > "$log_file" 2>&1 || true

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

  echo "[VAULT_HIT] Gemini 호출 생략 — vault 캐시 사용 (--force로 강제 재실행 가능)"
  echo ""
  echo "--- Vault Cache Result ---"
  echo "$cached_content" | sed '/^---$/,/^---$/d'
  return 0
}

# --- Run Gemini ---
run_gemini() {
  local model="${1:-}"
  local reasoning="${2:-}"
  local log_file="$LOG_DIR/gemini_${TASK_NAME}_${TIMESTAMP}.txt"

  if [ -z "$model" ]; then
    echo "[ERROR] Missing Gemini model for task: $TASK_NAME" >&2
    return 1
  fi

  if [ "${DRY_RUN:-false}" = "true" ]; then
    print_dry_run "$AGENT" "$model" "$reasoning"
    return 0
  fi

  # Vault check — skip Gemini if recent result cached in vault
  if vault_check; then return 0; fi

  dispatch_guard "gemini"
  echo "[DISPATCH] Gemini ($model) — task: $TASK_NAME"

  # Update queue status to dispatched
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "dispatched"
  [ -d "${QUEUE_TASK_DIR:-}" ] && sedi "s/\"model\": *\"[^\"]*\"/\"model\": \"$model\"/" "$QUEUE_TASK_DIR/meta.json"

  # Auto-append role checklist if role was inferred
  local gemini_task="$TASK"
  if [ -n "${SELECTED_ROLE:-}" ]; then
    local checklist_file="$SCRIPT_DIR/../configs/checklists/${SELECTED_ROLE}.md"
    if [ -f "$checklist_file" ]; then
      gemini_task="${TASK}

$(cat "$checklist_file")"
      echo "[CHECKLIST] Appended role checklist: ${SELECTED_ROLE}"
    fi
  fi

  # Write task to temp file and pass via stdin to avoid shell escaping issues
  # with long Korean prompts containing special characters ('-p "$TASK"' was silently failing)
  local tmp_prompt
  tmp_prompt="/tmp/gemini_prompt_$$.tmp"
  printf '%s' "$gemini_task" > "$tmp_prompt"

  gemini \
    --yolo \
    -m "$model" < "$tmp_prompt" 2>&1 \
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

  # Validate result — detect meta-response (Gemini said "completed" but returned no content)
  # Two patterns: (a) result too short, (b) result contains file-save or step-narration signals
  local clean_len
  clean_len=$(echo "$result" | grep -v "YOLO mode\|Loaded cached\|^$\|write_todos\|mark.*complete\|task.*complete\|completed.*task\|analysis.*done\|I have completed\|All tasks are complete" | wc -c)
  local has_file_save=false
  echo "$result" | grep -qiE "saved to|report is saved|file.*saved|저장했습니다|저장되었습니다" && has_file_save=true
  local has_narration=false
  # Narration-only response: many "I will/I have" lines but fewer than 3 markdown headers
  local header_count narration_count
  header_count=$(echo "$result" | grep -c "^##" || true)
  narration_count=$(echo "$result" | grep -cE "^(I will|I have|Now I|Next,|Okay,|I've)" || true)
  [ "$header_count" -lt 3 ] && [ "$narration_count" -gt 3 ] && has_narration=true
  if [ "$clean_len" -lt 300 ] || [ "$has_file_save" = "true" ] || [ "$has_narration" = "true" ]; then
    echo "[WARN] Gemini returned a meta-response (len=${clean_len}, file_save=${has_file_save}, narration=${has_narration}). Retrying once..."
    local retry_prompt
    retry_prompt="IMPORTANT: Output the full analysis content directly. Do NOT say 'I completed' or 'analysis is done'. Write everything inline now.

${gemini_task}"
    printf '%s' "$retry_prompt" > "$tmp_prompt"
    gemini \
      --yolo \
      -m "$model" < "$tmp_prompt" 2>&1 \
      | grep -Ev "YOLO mode is enabled|All tool calls will be automatically approved|Loaded cached credentials|\[WARN\]|EPERM|EACCES|operation not permitted|Error getting folder structure" \
      > "$log_file" || true
    rm -f "$tmp_prompt"
    result=$(cat "$log_file")
    echo "[RETRY] Gemini retry complete ($(echo "$result" | wc -c) chars)"
  fi

  # Success — update queue
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "completed"
  [ -d "${QUEUE_TASK_DIR:-}" ] && sedi "s|\"log_file\": *[^,]*|\"log_file\": \"$log_file\"|" "$QUEUE_TASK_DIR/meta.json"
  [ -d "${QUEUE_TASK_DIR:-}" ] && echo "$result" > "$QUEUE_TASK_DIR/result.md"

  # Save to vault — unless --no-vault (for intermediate pipeline steps)
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

${clean_result}
VAULTEOF
    echo "[VAULT] Saved → ~/vault/${vault_dir}/${vault_file}"
  else
    echo "[VAULT] Skipped (--no-vault)"
  fi

  # Strip YOLO noise lines, show clean output
  echo ""
  echo "--- Gemini Result ---"
  echo "$result" | grep -v "YOLO mode\|Loaded cached\|^$"
  return 0
}

# --- Shared status writer (OpenClaw Telegram 세션 → main 세션 상태 조회) ---
write_shared_status() {
  local agent="$1" status="$2" summary="${3:-}"
  local shared_dir="$HOME/.openclaw/shared"
  [ -d "$shared_dir" ] || return 0
  cat > "$shared_dir/status.md" << STATUSEOF
# OpenClaw Shared Status
_orchestrate.sh 자동 업데이트. OpenClaw Telegram 세션에서 읽어라._

## 마지막 업데이트
$(date '+%Y-%m-%d %H:%M:%S')

## 최근 작업
- 이름: ${TASK_NAME:-unknown}
- 에이전트: $agent
- 상태: $status
$([ -n "$summary" ] && printf '%s' "- 요약: $(echo "$summary" | head -3)")

## 큐 전체 현황
$(ls "$HOME/projects/agent-orchestration/queue/" 2>/dev/null | grep -v "activity" | tail -10 || echo "없음")
STATUSEOF
}

# --- Screen capture helper (openclaw nodes screen record 폴백) ---
# TODO: OpenClaw macOS 26 (Tahoe) 공식 지원 시 openclaw nodes screen record 로 교체
screen_capture() {
  local out="${1:-/tmp/openclaw_screen_$(date +%s).png}"
  screencapture -x "$out" 2>/dev/null && echo "$out"
}

# --- Run OpenClaw (browser / canvas / computer-use 워커) ---
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
import json
import sys

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
    value = find_value(
        obj,
        {"path", "filePath", "file_path", "screenshotPath", "screenshot_path", "output", "file", "filename"},
    )
    print("" if value is None else str(value))
elif mode == "text":
    value = find_value(
        obj,
        {"text", "content", "snapshot", "dom", "domText", "dom_text", "markdown", "value"},
    )
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

# --- Fallback logic ---
run_with_fallback_chain() {
  local chain_key="$1"
  local skip_family="${2:-}"
  local skip_model="${3:-}"
  local chain_tier="${4:-}"
  [ -n "$chain_tier" ] || chain_tier="$(fallback_subchain_tier_for_chain "$chain_key" "${SELECTED_COMPLEXITY_TIER:-}")"
  local chain_desc
  chain_desc="$(describe_fallback_chain "$chain_key" "$chain_tier")"

  if [ -n "$chain_tier" ]; then
    echo "[INFO] Attempting fallback chain: ${chain_key}(${chain_tier})${chain_desc:+ ($chain_desc)}"
  else
    echo "[INFO] Attempting fallback chain: ${chain_key}${chain_desc:+ ($chain_desc)}"
  fi

  local step_type step_value step_family step_model step_reasoning
  while IFS=$'\t' read -r step_type step_value step_family step_model step_reasoning; do
    [ -n "${step_type:-}" ] || continue
    step_type="${step_type//$'\r'/}"
    step_value="${step_value//$'\r'/}"
    step_family="${step_family//$'\r'/}"
    step_model="${step_model//$'\r'/}"
    step_reasoning="${step_reasoning//$'\r'/}"

    case "$step_type" in
      agent)
        if [ -n "$skip_model" ] && [ "$step_family" = "$skip_family" ] && [ "$step_model" = "$skip_model" ]; then
          echo "[FALLBACK] Skipping already-attempted step: $step_value ($step_model)"
          skip_family=""
          skip_model=""
          continue
        fi

        echo "[FALLBACK] Trying $step_value ($step_model)"
        case "$step_family" in
          gemini)
            if run_gemini "$step_model" "$step_reasoning"; then
              return 0
            fi
            ;;
          codex|chatgpt)
            if run_codex "$step_model" "$step_reasoning"; then
              return 0
            fi
            ;;
          *)
            echo "[WARN] Unsupported fallback agent family: $step_family"
            ;;
        esac
        ;;
      action)
        case "$step_value" in
          queue_and_wait|pause_and_notify)
            echo "[QUEUED] Fallback chain exhausted. Task queued for retry."
            [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "queued" "queued_reason" "fallback_exhausted"
            return 1
            ;;
          *)
            echo "[WARN] Unknown fallback action: $step_value"
            ;;
        esac
        ;;
    esac
  done < <(get_fallback_chain_steps "$chain_key" "$chain_tier")

  echo "[QUEUED] No executable fallback step succeeded. Task queued for retry."
  [ -d "${QUEUE_TASK_DIR:-}" ] && update_meta_status "$QUEUE_TASK_DIR" "queued" "queued_reason" "fallback_exhausted"
  return 1
}

run_with_fallback_code() {
  run_with_fallback_chain "code_generation" "${1:-}" "${2:-}"
}

run_with_fallback_research() {
  run_with_fallback_chain "research" "${1:-}" "${2:-}" "${3:-}"
}

# ============================================================
# Subcommands: --boot, --status, --resume, --complete, --cost, --clean
# ============================================================

do_mode() {
  local requested="${1:-}"
  local current_mode
  current_mode="$(get_active_mode)"

  if [ -z "$requested" ]; then
    echo "[MODE] Active: $current_mode"
    echo ""
    echo "Available modes:"
    while IFS=$'\t' read -r name desc; do
      [ -n "$name" ] || continue
      if [ "$name" = "$current_mode" ]; then
        echo "  - $name (active) ${desc:+: $desc}"
      else
        echo "  - $name${desc:+: $desc}"
      fi
    done < <(list_modes)
    exit 0
  fi

  if ! mode_exists "$requested" >/dev/null 2>&1; then
    echo "[ERROR] Invalid mode: $requested"
    echo "Valid modes:"
    while IFS=$'\t' read -r name _; do
      [ -n "$name" ] && echo "  - $name"
    done < <(list_modes)
    exit 1
  fi

  if ! set_active_mode "$requested" "manual"; then
    echo "[ERROR] Failed to set mode: $requested"
    exit 1
  fi

  local desc
  desc="$(describe_mode "$requested")"
  echo "[MODE] Switched: $current_mode -> $requested"
  [ -n "$desc" ] && echo "[MODE] $desc"
  exit 0
}

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
        "/c/Users/1/vault"           # pull-only (M1이 원본, 로컬 쓰기 금지)
        "$HOME/projects/agent-orchestration"
        "$HOME/projects/agent-orchestration-Codex_main"
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

  # Skills 자동 배포는 비활성화 — boot 시 자동 복사 시 수동 편집 내용 덮어씌워지는 문제 방지
  # 수동 배포: cp ~/projects/agent-orchestration/skills/foo.md ~/.claude/commands/foo.md

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

  local default_mode active_mode
  default_mode="$(get_default_mode)"
  if [ ! -f "$PERSIST_MODE_FILE" ]; then
    set_active_mode "$default_mode" "boot_reset" || true
  fi
  active_mode="$(get_active_mode)"
  echo "[MODE] Active: $active_mode"

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
        codex|codex-spark|chatgpt|chatgpt-mini|chatgpt-light|gemini|gemini-pro)
          select_dispatch_profile "$agent"
          if [[ "$agent" == gemini* ]]; then
            run_gemini "$SELECTED_MODEL" "$SELECTED_REASONING" || exit_code=$?
          else
            run_codex "$SELECTED_MODEL" "$SELECTED_REASONING" || exit_code=$?
          fi
          ;;
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
  python3 - "$QUEUE_DIR" "$REPO_DIR/archive/queue" "$period" "$AGENT_CONFIG_FILE" << 'PYEOF'
import json, sys
from pathlib import Path
from datetime import date, timedelta

try:
    import yaml  # type: ignore
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
  --mode)     shift; do_mode "${1:-}" ;;
  --chain)    do_chain "$@" ;;
esac

# --- Generate task brief from args ---
if [[ "${1:-}" == "--brief" ]]; then
  shift
  # Parse --role flag if present
  BRIEF_ROLE=""
  if [[ "${1:-}" == "--role" ]]; then
    BRIEF_ROLE="${2:-}"
    shift 2
  fi
  GOAL="${1:?Usage: orchestrate.sh --brief [--role reviewer|refactoring|documentation] <goal> <scope> <constraints>}"
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

## Stop Conditions
- All questions in the goal are answered (at least Moderate confidence)
- OR no further sources available and remaining gaps are documented
- OR scope/budget exhausted with partial findings clearly labeled
BRIEF_EOF
  # Append role-specific checklist if --role was given
  if [ -n "$BRIEF_ROLE" ]; then
    CHECKLIST_FILE="$SCRIPT_DIR/../configs/checklists/${BRIEF_ROLE}.md"
    if [ -f "$CHECKLIST_FILE" ]; then
      printf '\n' >> "$BRIEF_FILE"
      cat "$CHECKLIST_FILE" >> "$BRIEF_FILE"
      echo "[BRIEF] Role checklist appended: $BRIEF_ROLE"
    else
      echo "[WARN] Checklist not found: $CHECKLIST_FILE (available: reviewer, refactoring, documentation)"
    fi
  fi
  echo "[BRIEF] Generated: $BRIEF_FILE"
  echo "$BRIEF_FILE"
  exit 0
fi

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
ACTIVE_MODE="$(get_active_mode)"
export ACTIVE_MODE
echo "[ROUTER] mode=$ACTIVE_MODE"
case "$AGENT" in
  codex)
    select_dispatch_profile "$AGENT"
    run_codex "$SELECTED_MODEL" "$SELECTED_REASONING" || run_with_fallback_code "$SELECTED_FAMILY" "$SELECTED_MODEL"
    ;;
  codex-spark)
    select_dispatch_profile "$AGENT"
    run_codex "$SELECTED_MODEL" "$SELECTED_REASONING" || run_with_fallback_code "$SELECTED_FAMILY" "$SELECTED_MODEL"
    ;;
  gemini)
    select_dispatch_profile "$AGENT"
    run_gemini "$SELECTED_MODEL" "$SELECTED_REASONING" || run_with_fallback_research "$SELECTED_FAMILY" "$SELECTED_MODEL"
    ;;
  gemini-pro)
    select_dispatch_profile "$AGENT"
    run_gemini "$SELECTED_MODEL" "$SELECTED_REASONING" || run_with_fallback_research "$SELECTED_FAMILY" "$SELECTED_MODEL"
    ;;
  chatgpt)
    select_dispatch_profile "$AGENT"
    run_codex "$SELECTED_MODEL" "$SELECTED_REASONING" || run_with_fallback_chain "general" "$SELECTED_FAMILY" "$SELECTED_MODEL"
    ;;
  chatgpt-mini)
    select_dispatch_profile "$AGENT"
    run_codex "$SELECTED_MODEL" "$SELECTED_REASONING" || run_with_fallback_chain "general" "$SELECTED_FAMILY" "$SELECTED_MODEL"
    ;;
  chatgpt-light)
    select_dispatch_profile "$AGENT"
    run_codex "$SELECTED_MODEL" "$SELECTED_REASONING" || run_with_fallback_chain "general" "$SELECTED_FAMILY" "$SELECTED_MODEL"
    ;;
  openclaw)
    enforce_mode_gate "openclaw" "medium" "" || exit 1
    run_openclaw "medium"
    ;;
  openclaw-high)
    enforce_mode_gate "openclaw" "high" "" || exit 1
    run_openclaw "high"
    ;;
  codex-fallback)
    run_with_fallback_code
    ;;
  gemini-fallback)
    run_with_fallback_research
    ;;
  *)
    echo "[ERROR] Unknown agent: $AGENT"
    echo "Available: codex, codex-spark, chatgpt, chatgpt-mini, chatgpt-light, gemini, gemini-pro, openclaw, openclaw-high"
    echo "Options:   run <blueprint_file> [--var key=value ...]"
    echo "           --mode [name], schema [agent] [--json]"
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
