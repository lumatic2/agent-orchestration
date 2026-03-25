#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${_SELF_HEAL_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_SELF_HEAL_LOADED=1

classify_error() {
  local exit_code="${1:-0}"
  local output_text="${2:-}"

  OUTPUT_TEXT="$output_text" TMPDIR="${PYTMPDIR:-${TMPDIR:-}}" python - "$exit_code" <<'PY'
import os
import sys

exit_code = int(sys.argv[1])
text = os.environ.get("OUTPUT_TEXT", "")

if exit_code == 124 or "timeout" in text.lower():
    print("TIMEOUT")
elif "ImportError" in text or "ModuleNotFoundError" in text:
    print("MISSING_DEPS")
elif "MemoryError" in text or "Killed" in text or "OOM" in text:
    print("OOM")
elif "NaN" in text or "Inf" in text or "inf" in text:
    print("NaN_INF")
elif "JSONDecodeError" in text or "XMLSyntaxError" in text or "yaml.scanner" in text:
    print("PARSE_FAIL")
elif exit_code != 0 and ("HTTP" in text or "429" in text or "403" in text or "500" in text):
    print("API_FAIL")
elif text.strip() == "":
    print("EMPTY_OUTPUT")
else:
    print("UNKNOWN")
PY
}

generate_fix_prompt() {
  local error_category="${1:-UNKNOWN}"
  local original_prompt="${2:-}"
  local error_output="${3:-}"
  local instruction=""

  case "$error_category" in
    TIMEOUT)
      instruction="Simplify or reduce scope of the following task. Focus on essential output only and complete quickly." ;;
    API_FAIL)
      instruction="The API call failed. Retry with alternative approach, add retry-safe behavior, and avoid unstable external dependency patterns." ;;
    MISSING_DEPS)
      instruction="Add missing import or install instruction and provide a dependency-safe solution that runs in the existing environment." ;;
    OOM)
      instruction="Reduce memory usage, use batching or sampling, and avoid loading large data at once." ;;
    NaN_INF)
      instruction="Fix numerical instability. Add stable calculations, guard divisions, and prevent NaN/Inf outputs." ;;
    PARSE_FAIL)
      instruction="Fix output format to valid JSON/XML and ensure strict parseable structure." ;;
    EMPTY_OUTPUT|UNKNOWN|*)
      instruction="The previous attempt failed. Analyze and fix the task with a robust, explicit output." ;;
  esac

  printf '%s\n\nOriginal task:\n%s\n\nPrevious error output:\n%s\n' "$instruction" "$original_prompt" "$error_output"
}

_json_escape() {
  local s="${1:-}"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

log_retry() {
  local attempt="${1:-0}"
  local error="${2:-UNKNOWN}"
  local state_dir="${STATE_DIR:-.}"
  local stage="${CURRENT_STAGE:-unknown}"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  mkdir -p "$state_dir"
  printf '{"stage":"%s","attempt":%s,"error":"%s","ts":"%s"}\n' \
    "$(_json_escape "$stage")" \
    "$attempt" \
    "$(_json_escape "$error")" \
    "$ts" >> "$state_dir/retry_log.jsonl"
}

run_with_retry() {
  local max_retries="2"
  if [[ $# -ge 4 ]]; then
    max_retries="$1"
    shift
  fi

  local agent="${1:-}"
  local prompt="${2:-}"
  local task_name="${3:-}"

  if [[ -z "${ORCH:-}" || -z "$agent" || -z "$task_name" ]]; then
    LAST_RETRY_ERROR="UNKNOWN"
    return 1
  fi

  local attempt=1
  local current_prompt="$prompt"
  local last_error="UNKNOWN"

  while (( attempt <= max_retries + 1 )); do
    local out_file
    out_file="$(mktemp)"

    set +e
    bash "$ORCH" "$agent" "$current_prompt" "$task_name" >"$out_file" 2>&1
    local cmd_exit=$?
    set -e

    local output_text
    output_text="$(cat "$out_file")"
    rm -f "$out_file"

    if [[ $cmd_exit -eq 0 && "$output_text" =~ [^[:space:]] ]]; then
      printf '%s\n' "$output_text"
      LAST_RETRY_ERROR=""
      return 0
    fi

    last_error="$(classify_error "$cmd_exit" "$output_text")"
    log_retry "$attempt" "$last_error"

    if (( attempt > max_retries )); then
      break
    fi

    current_prompt="$(generate_fix_prompt "$last_error" "$prompt" "$output_text")"
    attempt=$((attempt + 1))
  done

  LAST_RETRY_ERROR="$last_error"
  return 1
}

self_heal_self_test() {
  local failed=0

  _assert_eq() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$expected" == "$actual" ]]; then
      printf 'PASS %s\n' "$name"
    else
      printf 'FAIL %s expected=%s actual=%s\n' "$name" "$expected" "$actual"
      failed=1
    fi
  }

  _assert_non_empty() {
    local name="$1"
    local value="$2"
    if [[ "$value" =~ [^[:space:]] ]]; then
      printf 'PASS %s\n' "$name"
    else
      printf 'FAIL %s empty\n' "$name"
      failed=1
    fi
  }

  _assert_eq "classify TIMEOUT exit124" "TIMEOUT" "$(classify_error 124 "")"
  _assert_eq "classify MISSING_DEPS" "MISSING_DEPS" "$(classify_error 1 "ModuleNotFoundError: x")"
  _assert_eq "classify OOM" "OOM" "$(classify_error 1 "Killed")"
  _assert_eq "classify NaN_INF" "NaN_INF" "$(classify_error 0 "value=Inf")"
  _assert_eq "classify PARSE_FAIL" "PARSE_FAIL" "$(classify_error 1 "JSONDecodeError")"
  _assert_eq "classify API_FAIL" "API_FAIL" "$(classify_error 2 "HTTP 429")"
  _assert_eq "classify EMPTY_OUTPUT" "EMPTY_OUTPUT" "$(classify_error 0 "   ")"
  _assert_eq "classify UNKNOWN" "UNKNOWN" "$(classify_error 1 "other error")"

  local categories="TIMEOUT API_FAIL MISSING_DEPS OOM NaN_INF PARSE_FAIL EMPTY_OUTPUT UNKNOWN"
  local c
  for c in $categories; do
    _assert_non_empty "fix_prompt $c" "$(generate_fix_prompt "$c" "orig" "err")"
  done

  if [[ $failed -eq 0 ]]; then
    printf 'PASS self_heal tests\n'
    return 0
  fi

  printf 'FAIL self_heal tests\n'
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" && "${1:-}" == "--test" ]]; then
  self_heal_self_test
fi