#!/usr/bin/env bash

set -euo pipefail

[[ -n "${_CIRCUIT_BREAKER_LOADED:-}" ]] && return 0
_CIRCUIT_BREAKER_LOADED=1

STATE_DIR="${STATE_DIR:-${PWD}/state}"
_CIRCUIT_STATE_FILE_NAME="circuit_state.json"
_CIRCUIT_OPEN_WINDOW_SEC=1800

_circuit_state_file() {
  printf '%s/%s' "$STATE_DIR" "$_CIRCUIT_STATE_FILE_NAME"
}

_circuit_now_iso() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

_circuit_ensure_state_file() {
  mkdir -p "$STATE_DIR"
  local state_file
  state_file="$(_circuit_state_file)"
  if [[ ! -f "$state_file" ]]; then
    printf '{"sources":{}}\n' > "$state_file"
  fi
}

_circuit_source_key() {
  printf '%s' "$1" | tr '[:lower:]-.' '[:upper:]__'
}

_circuit_get_var() {
  local name="$1"
  if [[ -n "${!name-}" ]]; then
    printf '%s' "${!name}"
  fi
}

_circuit_resolve_source() {
  local source_name="$1"
  local default_timeout="$2"

  local ukey
  ukey="$(_circuit_source_key "$source_name")"

  local url_var1="CIRCUIT_URL_${ukey}"
  local url_var2="${source_name}_url"
  local parse_var1="CIRCUIT_PARSE_CMD_${ukey}"
  local parse_var2="${source_name}_parse_cmd"
  local timeout_var1="CIRCUIT_TIMEOUT_${ukey}"
  local timeout_var2="${source_name}_timeout"

  local resolved_url resolved_parse resolved_timeout
  resolved_url="$(_circuit_get_var "$url_var1")"
  [[ -z "$resolved_url" ]] && resolved_url="$(_circuit_get_var "$url_var2")"

  resolved_parse="$(_circuit_get_var "$parse_var1")"
  [[ -z "$resolved_parse" ]] && resolved_parse="$(_circuit_get_var "$parse_var2")"

  resolved_timeout="$(_circuit_get_var "$timeout_var1")"
  [[ -z "$resolved_timeout" ]] && resolved_timeout="$(_circuit_get_var "$timeout_var2")"
  [[ -z "$resolved_timeout" ]] && resolved_timeout="$default_timeout"

  if [[ -n "$resolved_url" && -n "$resolved_parse" ]]; then
    _CB_RESOLVED_URL="$resolved_url"
    _CB_RESOLVED_PARSE_CMD="$resolved_parse"
    _CB_RESOLVED_TIMEOUT="$resolved_timeout"
    return 0
  fi

  return 1
}

_circuit_is_open_and_recent() {
  local source_name="$1"
  local state_file
  state_file="$(_circuit_state_file)"

  python3 -c 'import json,sys,time,datetime
source = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    print("0")
    raise SystemExit(0)
node = data.get("sources", {}).get(source, {})
if node.get("status") != "open":
    print("0")
    raise SystemExit(0)
trip = node.get("tripped_at")
if not trip:
    print("0")
    raise SystemExit(0)
try:
    dt = datetime.datetime.strptime(trip, "%Y-%m-%dT%H:%M:%S%z")
except Exception:
    try:
        dt = datetime.datetime.fromisoformat(trip)
    except Exception:
        print("0")
        raise SystemExit(0)
age = time.time() - dt.timestamp()
print("1" if age < 1800 else "0")
' "$source_name" < "$state_file"
}

_circuit_update_source() {
  local source_name="$1"
  local mode="$2"
  local state_file tmp_file
  state_file="$(_circuit_state_file)"
  tmp_file="$(mktemp "${STATE_DIR}/circuit_state.XXXXXX")"

  python3 -c 'import json,sys,datetime
source = sys.argv[1]
mode = sys.argv[2]
try:
    data = json.load(sys.stdin)
except Exception:
    data = {"sources": {}}
if "sources" not in data or not isinstance(data["sources"], dict):
    data["sources"] = {}
node = data["sources"].get(source, {"failures": 0, "status": "closed", "tripped_at": None})
node.setdefault("failures", 0)
node.setdefault("status", "closed")
node.setdefault("tripped_at", None)
if mode == "success":
    node["failures"] = 0
    node["status"] = "closed"
    node["tripped_at"] = None
elif mode == "failure":
    node["failures"] = int(node.get("failures", 0)) + 1
    if node["failures"] >= 3:
        node["status"] = "open"
        node["tripped_at"] = datetime.datetime.now(datetime.timezone.utc).astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")
    elif node.get("status") != "open":
        node["status"] = "closed"
        node["tripped_at"] = None
else:
    raise SystemExit(1)
data["sources"][source] = node
json.dump(data, sys.stdout, ensure_ascii=False, separators=(",", ":"))
' "$source_name" "$mode" < "$state_file" > "$tmp_file"

  mv "$tmp_file" "$state_file"
}

_circuit_try_fallback() {
  local timeout_sec="$1"
  shift
  local fallbacks=("$@")

  if [[ ${#fallbacks[@]} -eq 0 ]]; then
    return 1
  fi

  local next_source="${fallbacks[0]}"
  local rest=("${fallbacks[@]:1}")

  if _circuit_resolve_source "$next_source" "$timeout_sec"; then
    circuit_call "$next_source" "$_CB_RESOLVED_URL" "$_CB_RESOLVED_TIMEOUT" "$_CB_RESOLVED_PARSE_CMD" "${rest[@]}"
    return $?
  fi

  _circuit_try_fallback "$timeout_sec" "${rest[@]}"
}

circuit_call() {
  local source_name="$1"
  local url="$2"
  local timeout_sec="$3"
  local parse_cmd="$4"
  shift 4
  local fallbacks=("$@")

  _circuit_ensure_state_file

  local is_open_recent
  is_open_recent="$(_circuit_is_open_and_recent "$source_name")"
  if [[ "$is_open_recent" == "1" ]]; then
    _circuit_try_fallback "$timeout_sec" "${fallbacks[@]}"
    return $?
  fi

  local output=""
  if output="$(curl -sL --max-time "$timeout_sec" "$url" | eval "$parse_cmd")" && [[ -n "$output" ]]; then
    _circuit_update_source "$source_name" "success"
    printf '%s\n' "$output"
    return 0
  fi

  _circuit_update_source "$source_name" "failure"
  _circuit_try_fallback "$timeout_sec" "${fallbacks[@]}"
}

circuit_reset() {
  _circuit_ensure_state_file
  local state_file tmp_file
  state_file="$(_circuit_state_file)"
  tmp_file="$(mktemp "${STATE_DIR}/circuit_state.XXXXXX")"

  python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = {"sources": {}}
if "sources" not in data or not isinstance(data["sources"], dict):
    data["sources"] = {}
for k, node in list(data["sources"].items()):
    if not isinstance(node, dict):
        node = {}
    node["failures"] = 0
    node["status"] = "closed"
    node["tripped_at"] = None
    data["sources"][k] = node
json.dump(data, sys.stdout, ensure_ascii=False, separators=(",", ":"))
' < "$state_file" > "$tmp_file"

  mv "$tmp_file" "$state_file"
}

circuit_status() {
  _circuit_ensure_state_file
  local state_file
  state_file="$(_circuit_state_file)"

  python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = {"sources": {}}
sources = data.get("sources", {})
print("source\tstatus\tfailures\ttripped_at")
for name in sorted(sources.keys()):
    node = sources.get(name, {}) if isinstance(sources.get(name), dict) else {}
    status = node.get("status", "closed")
    failures = node.get("failures", 0)
    tripped_at = node.get("tripped_at", None)
    print(f"{name}\t{status}\t{failures}\t{'' if tripped_at is None else tripped_at}")
' < "$state_file"
}

_circuit_set_source_state_for_test() {
  local source_name="$1"
  local failures="$2"
  local status="$3"
  local tripped_at="$4"

  _circuit_ensure_state_file
  local state_file tmp_file
  state_file="$(_circuit_state_file)"
  tmp_file="$(mktemp "${STATE_DIR}/circuit_state.XXXXXX")"

  python3 -c 'import json,sys
source, failures, status, tripped = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
try:
    data = json.load(sys.stdin)
except Exception:
    data = {"sources": {}}
if "sources" not in data or not isinstance(data["sources"], dict):
    data["sources"] = {}
if tripped == "__NONE__":
    tripped_val = None
else:
    tripped_val = tripped
data["sources"][source] = {"failures": failures, "status": status, "tripped_at": tripped_val}
json.dump(data, sys.stdout, ensure_ascii=False, separators=(",", ":"))
' "$source_name" "$failures" "$status" "$tripped_at" < "$state_file" > "$tmp_file"

  mv "$tmp_file" "$state_file"
}

_circuit_self_test() {
  local failed=0
  local tmp_root
  tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/circuit_test.XXXXXX" 2>/dev/null || mktemp -d -t circuit_test)"

  local old_state_dir="${STATE_DIR:-}"
  STATE_DIR="$tmp_root/state"
  mkdir -p "$STATE_DIR"

  local payload_file="$tmp_root/payload.txt"
  printf 'ok\n' > "$payload_file"

  local server_port="18080"
  python3 -m http.server "$server_port" --bind 127.0.0.1 --directory "$tmp_root" >/dev/null 2>&1 &
  local server_pid=$!
  local ready=0
  for _j in 1 2 3 4 5; do
    if curl -sL --max-time 1 "http://127.0.0.1:${server_port}/payload.txt" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 1
  done
  [[ "$ready" == "1" ]] || failed=1

  local src="primary"
  local url="http://127.0.0.1:${server_port}/payload.txt"
  local bad_url="http://127.0.0.1:9/unreachable"

  for _i in 1 2 3; do
    circuit_call "$src" "$bad_url" 1 "cat" >/dev/null 2>&1 || true
  done

  local opened
  opened="$(python3 -c 'import json,sys
obj = json.load(open(sys.argv[1], encoding="utf-8"))
node = obj.get("sources", {}).get("primary", {})
ok = node.get("status") == "open" and int(node.get("failures", 0)) >= 3
print("1" if ok else "0")
' "$(_circuit_state_file)")"
  [[ "$opened" == "1" ]] || failed=1

  export CIRCUIT_URL_BACKUP="$url"
  export CIRCUIT_PARSE_CMD_BACKUP="cat"
  export CIRCUIT_TIMEOUT_BACKUP="2"

  local fallback_out
  fallback_out="$(circuit_call "$src" "$url" 2 "cat" "backup" 2>/dev/null || true)"
  [[ "$fallback_out" == "ok" ]] || failed=1

  local old_trip
  old_trip="$(python3 -c 'import datetime
print((datetime.datetime.now(datetime.timezone.utc).astimezone()-datetime.timedelta(minutes=31)).strftime("%Y-%m-%dT%H:%M:%S%z"))')"
  _circuit_set_source_state_for_test "$src" 3 "open" "$old_trip"

  local reset_out
  reset_out="$(circuit_call "$src" "$url" 2 "cat" 2>/dev/null || true)"
  [[ "$reset_out" == "ok" ]] || failed=1

  local closed
  closed="$(python3 -c 'import json,sys
obj = json.load(open(sys.argv[1], encoding="utf-8"))
node = obj.get("sources", {}).get("primary", {})
ok = node.get("status") == "closed" and int(node.get("failures", 0)) == 0 and node.get("tripped_at") is None
print("1" if ok else "0")
' "$(_circuit_state_file)")"
  [[ "$closed" == "1" ]] || failed=1

  kill "$server_pid" >/dev/null 2>&1 || true
  rm -rf "$tmp_root"
  if [[ -n "$old_state_dir" ]]; then
    STATE_DIR="$old_state_dir"
  fi

  if [[ "$failed" -eq 0 ]]; then
    echo "PASS"
    return 0
  fi
  echo "FAIL"
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ "${1:-}" == "--test" ]]; then
    _circuit_self_test
  fi
fi
