#!/usr/bin/env bash

if [[ -n "${_GATE_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_GATE_LOADED=1

set -euo pipefail

: "${STATE_DIR:=.state}"

_gate_python_bin() {
  if [[ -n "${_GATE_PYTHON_BIN:-}" ]]; then
    printf '%s\n' "$_GATE_PYTHON_BIN"
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    _GATE_PYTHON_BIN="$(command -v python3)"
  elif command -v python >/dev/null 2>&1; then
    _GATE_PYTHON_BIN="$(command -v python)"
  else
    echo "gate.sh: python3/python is required" >&2
    return 1
  fi

  printf '%s\n' "$_GATE_PYTHON_BIN"
}

_gate_trueish() {
  local v
  v="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$v" in
    1|true|yes|on|y)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_gate_now_iso8601() {
  "$( _gate_python_bin )" - <<'PY'
from datetime import datetime, timezone
print(datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z'))
PY
}

_gate_next_version_number() {
  local max n dir
  max=0
  for dir in "$STATE_DIR".v*; do
    [[ -d "$dir" ]] || continue
    n="${dir##*.v}"
    case "$n" in
      ''|*[!0-9]*)
        continue
        ;;
    esac
    if (( n > max )); then
      max="$n"
    fi
  done
  printf '%s\n' "$((max + 1))"
}

_gate_log_append() {
  local stage result action ts line
  stage="$1"
  result="$2"
  action="$3"
  ts="$(_gate_now_iso8601)"

  line="$(STAGE="$stage" RESULT="$result" ACTION="$action" TS="$ts" "$( _gate_python_bin )" - <<'PY'
import json, os
row = {
    'stage': os.environ['STAGE'],
    'result': os.environ['RESULT'],
    'action': os.environ['ACTION'],
    'ts': os.environ['TS'],
}
print(json.dumps(row, separators=(',', ':')))
PY
)"

  printf '%s\n' "$line" >> "$STATE_DIR/gate_log.jsonl"
}

_gate_read_decision() {
  local stage
  stage="$1"
  STAGE_NAME="$stage" CONFIG_PATH="$STATE_DIR/gate_config.json" "$( _gate_python_bin )" - <<'PY'
import json, os
with open(os.environ['CONFIG_PATH'], 'r', encoding='utf-8') as f:
    cfg = json.load(f)
auto_all = bool(cfg.get('auto_approve_all', False))
gate = cfg.get('gates', {}).get(os.environ['STAGE_NAME'], {})
auto_gate = bool(gate.get('auto_approve', False))
on_reject = gate.get('on_reject', 'stop')
print('1' if auto_all else '0')
print('1' if auto_gate else '0')
print(str(on_reject))
PY
}

gate_init() {
  mkdir -p "$STATE_DIR"

  CONFIG_PATH="$STATE_DIR/gate_config.json" "$( _gate_python_bin )" - <<'PY'
import json, os
path = os.environ['CONFIG_PATH']
default_gates = {
    'S06': {'auto_approve': False, 'timeout_min': 60, 'on_reject': 'stop'},
    'S12': {'auto_approve': False, 'timeout_min': 30, 'on_reject': 'stop'},
    'S14': {'auto_approve': False, 'timeout_min': 60, 'on_reject': 'stop'},
    'S15': {'auto_approve': False, 'timeout_min': 60, 'on_reject': 'rollback_S13'},
}
if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        try:
            cfg = json.load(f)
        except Exception:
            cfg = {}
else:
    cfg = {}
if not isinstance(cfg, dict):
    cfg = {}
cfg.setdefault('gates', {})
if not isinstance(cfg['gates'], dict):
    cfg['gates'] = {}
for stage, defaults in default_gates.items():
    gate = cfg['gates'].get(stage)
    if not isinstance(gate, dict):
        gate = {}
    gate.setdefault('auto_approve', defaults['auto_approve'])
    gate.setdefault('timeout_min', defaults['timeout_min'])
    gate.setdefault('on_reject', defaults['on_reject'])
    cfg['gates'][stage] = gate
cfg['auto_approve_all'] = bool(cfg.get('auto_approve_all', False))
versions = cfg.get('versions', {})
if not isinstance(versions, dict):
    versions = {}
cfg['versions'] = versions
with open(path, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
PY

  if [[ ! -f "$STATE_DIR/gate_log.jsonl" ]]; then
    : > "$STATE_DIR/gate_log.jsonl"
  fi
}

gate_check() {
  local stage result decision auto_all auto_gate on_reject action rollback_target
  stage="$1"
  result="$2"

  gate_init

  case "$result" in
    pass|fail|warn)
      ;;
    *)
      echo "gate_check: invalid check_result '$result' (expected pass|fail|warn)" >&2
      return 1
      ;;
  esac

  decision="$(_gate_read_decision "$stage")"
  auto_all="$(printf '%s\n' "$decision" | sed -n '1p')"
  auto_gate="$(printf '%s\n' "$decision" | sed -n '2p')"
  on_reject="$(printf '%s\n' "$decision" | sed -n '3p')"

  action="proceed"
  if _gate_trueish "${GATE_AUTO_APPROVE_ALL:-}" || [[ "$auto_all" == "1" || "$auto_gate" == "1" ]]; then
    action="auto_pass"
    _gate_log_append "$stage" "$result" "$action"
    return 0
  fi

  case "$result" in
    pass)
      action="proceed"
      _gate_log_append "$stage" "$result" "$action"
      return 0
      ;;
    warn)
      action="warn_proceed"
      echo "gate_check: warning at $stage" >&2
      _gate_log_append "$stage" "$result" "$action"
      return 0
      ;;
    fail)
      if [[ "$on_reject" == rollback_* ]]; then
        rollback_target="${on_reject#rollback_}"
        if [[ -n "$rollback_target" ]]; then
          gate_version "$stage"
          GATE_ROLLBACK_TARGET="$rollback_target"
          export GATE_ROLLBACK_TARGET
          action="rollback_${rollback_target}"
        else
          action="blocked"
        fi
      else
        action="blocked"
      fi
      _gate_log_append "$stage" "$result" "$action"
      return 1
      ;;
  esac
}

gate_version() {
  local stage next
  stage="$1"
  next="$(_gate_next_version_number)"

  if [[ -d "$STATE_DIR" ]]; then
    mv "$STATE_DIR" "$STATE_DIR.v$next"
  fi

  mkdir -p "$STATE_DIR"

  gate_init

  STAGE_NAME="$stage" VERSION_NUM="$next" CONFIG_PATH="$STATE_DIR/gate_config.json" "$( _gate_python_bin )" - <<'PY'
import json, os
path = os.environ['CONFIG_PATH']
stage = os.environ['STAGE_NAME']
version = int(os.environ['VERSION_NUM'])
with open(path, 'r', encoding='utf-8') as f:
    cfg = json.load(f)
versions = cfg.setdefault('versions', {})
vals = versions.get(stage)
if not isinstance(vals, list):
    vals = []
if version not in vals:
    vals.append(version)
vals.sort()
versions[stage] = vals
with open(path, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
PY
}

gate_restore_version() {
  local stage version target backup
  stage="$1"
  version="$2"
  target="$STATE_DIR.v$version"

  [[ -d "$target" ]] || {
    echo "gate_restore_version: missing version directory '$target'" >&2
    return 1
  }

  if [[ -d "$STATE_DIR" ]]; then
    backup="$(_gate_next_version_number)"
    mv "$STATE_DIR" "$STATE_DIR.v$backup"
  fi

  mkdir -p "$STATE_DIR"
  cp -R "$target/." "$STATE_DIR/"

  gate_init

  STAGE_NAME="$stage" VERSION_NUM="$version" CONFIG_PATH="$STATE_DIR/gate_config.json" "$( _gate_python_bin )" - <<'PY'
import json, os
path = os.environ['CONFIG_PATH']
stage = os.environ['STAGE_NAME']
version = int(os.environ['VERSION_NUM'])
with open(path, 'r', encoding='utf-8') as f:
    cfg = json.load(f)
versions = cfg.setdefault('versions', {})
vals = versions.get(stage)
if not isinstance(vals, list):
    vals = []
if version not in vals:
    vals.append(version)
vals.sort()
versions[stage] = vals
with open(path, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
PY
}

gate_history() {
  local log_path
  log_path="$STATE_DIR/gate_log.jsonl"

  if [[ ! -f "$log_path" || ! -s "$log_path" ]]; then
    echo "No gate history."
    return 0
  fi

  LOG_PATH="$log_path" "$( _gate_python_bin )" - <<'PY'
import json, os
path = os.environ['LOG_PATH']
with open(path, 'r', encoding='utf-8') as f:
    for raw in f:
        line = raw.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except Exception:
            continue
        ts = row.get('ts', '-')
        stage = row.get('stage', '-')
        result = row.get('result', '-')
        action = row.get('action', '-')
        print(f"{ts} | {stage} | {result} | {action}")
PY
}

gate_set_auto_approve() {
  local target value bval
  target="$1"
  value="$2"

  case "$value" in
    true)
      bval=1
      ;;
    false)
      bval=0
      ;;
    *)
      echo "gate_set_auto_approve: value must be true|false" >&2
      return 1
      ;;
  esac

  gate_init

  TARGET="$target" BVAL="$bval" CONFIG_PATH="$STATE_DIR/gate_config.json" "$( _gate_python_bin )" - <<'PY'
import json, os
path = os.environ['CONFIG_PATH']
target = os.environ['TARGET']
bval = bool(int(os.environ['BVAL']))
with open(path, 'r', encoding='utf-8') as f:
    cfg = json.load(f)
if target == 'all':
    cfg['auto_approve_all'] = bval
else:
    gates = cfg.setdefault('gates', {})
    gate = gates.get(target)
    if not isinstance(gate, dict):
        gate = {'on_reject': 'stop'}
    gate['auto_approve'] = bval
    gate.setdefault('on_reject', 'stop')
    gates[target] = gate
with open(path, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
PY
}

gate_self_test() {
  local tmp failures total
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/gate-test.XXXXXX")"
  failures=0
  total=0

  _GATE_TEST_TMP="$tmp"
  trap 'rm -rf "${_GATE_TEST_TMP:-}"' EXIT

  STATE_DIR="$tmp/state"
  export STATE_DIR

  run_test() {
    local name
    name="$1"
    total=$((total + 1))
    if "$@" >/dev/null 2>&1; then
      echo "PASS $name"
    else
      echo "FAIL $name"
      failures=$((failures + 1))
    fi
  }

  test_pass() {
    gate_init
    gate_check S06 pass
  }

  test_warn() {
    gate_init
    gate_check S06 warn
  }

  test_fail_block() {
    gate_init
    if gate_check S06 fail; then
      return 1
    fi
    return 0
  }

  test_version_created() {
    gate_init
    gate_version S12
    [[ -d "$STATE_DIR.v1" ]]
  }

  test_auto_approve_all() {
    gate_init
    gate_set_auto_approve all true
    gate_check S06 fail
  }

  test_auto_approve_env() {
    gate_init
    gate_set_auto_approve all false
    GATE_AUTO_APPROVE_ALL=true gate_check S06 fail
  }

  test_fail_rollback() {
    gate_init
    CONFIG_PATH="$STATE_DIR/gate_config.json" "$( _gate_python_bin )" - <<'PY'
import json, os
path = os.environ['CONFIG_PATH']
with open(path, 'r', encoding='utf-8') as f:
    cfg = json.load(f)
cfg['gates']['S14']['on_reject'] = 'rollback_S12'
with open(path, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
PY
    unset GATE_ROLLBACK_TARGET || true
    if gate_check S14 fail; then
      return 1
    fi
    [[ "${GATE_ROLLBACK_TARGET:-}" == "S12" ]]
  }

  run_test test_pass
  run_test test_warn
  run_test test_fail_block
  run_test test_version_created
  run_test test_auto_approve_all
  run_test test_auto_approve_env
  run_test test_fail_rollback

  echo "Summary: $((total - failures))/$total passed"

  if (( failures > 0 )); then
    return 1
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ "${1:-}" == "--test" ]]; then
    gate_self_test
    exit $?
  fi
  echo "gate.sh is a library. Use: source scripts/lib/gate.sh" >&2
  exit 1
fi
