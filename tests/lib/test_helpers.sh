#!/usr/bin/env bash
# test_helpers.sh — Assertion functions for test suite

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0
CURRENT_TEST=""

# Colors (safe for Git Bash)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

start_test() {
  CURRENT_TEST="$1"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  printf "  %-60s " "$CURRENT_TEST"
}

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC}\n"
}

fail() {
  local msg="${1:-}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}FAIL${NC}\n"
  [ -n "$msg" ] && echo "    → $msg"
}

log_info() {
  local msg="$1"
  echo "[INFO] $msg"
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-expected '$1' got '$2'}"
  if [ "$expected" = "$actual" ]; then
    pass
  else
    fail "$msg"
  fi
}

assert_neq() {
  local not_expected="$1" actual="$2" msg="${3:-expected not '$1' but got it}"
  if [ "$not_expected" != "$actual" ]; then
    pass
  else
    fail "$msg"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-'$1' does not contain '$2'}"
  if echo "$haystack" | grep -qF "$needle"; then
    pass
  else
    fail "output does not contain '$needle'"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if echo "$haystack" | grep -qF "$needle"; then
    fail "output unexpectedly contains '$needle'"
  else
    pass
  fi
}

assert_file_exists() {
  local path="$1" msg="${2:-file not found: $1}"
  if [ -f "$path" ]; then
    pass
  else
    fail "$msg"
  fi
}

assert_file_not_exists() {
  local path="$1"
  if [ ! -f "$path" ]; then
    pass
  else
    fail "file should not exist: $path"
  fi
}

assert_dir_exists() {
  local path="$1"
  if [ -d "$path" ]; then
    pass
  else
    fail "directory not found: $path"
  fi
}

assert_exit_code() {
  local expected="$1" actual="$2"
  if [ "$expected" = "$actual" ]; then
    pass
  else
    fail "expected exit code $expected, got $actual"
  fi
}

assert_not_empty() {
  local value="$1" msg="${2:-expected non-empty value}"
  if [ -n "$value" ]; then
    pass
  else
    fail "$msg"
  fi
}

assert_matches() {
  local haystack="$1" pattern="$2"
  if echo "$haystack" | grep -qE "$pattern"; then
    pass
  else
    fail "output does not match pattern '$pattern'"
  fi
}

sedi() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

now_iso() { date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || date +%Y-%m-%dT%H:%M:%S; }

update_meta_status() {
  local dir="$1" new_status="$2"
  local extra_field="${3:-}" extra_value="${4:-}"
  local meta="$dir/meta.json"
  [ -f "$meta" ] || return 1
  sedi "s/\"status\": *\"[^\"]*\"/\"status\": \"$new_status\"/" "$meta"
  case "$new_status" in
    dispatched) sedi "s/\"dispatched\": *[^,]*/\"dispatched\": \"$(now_iso)\"/" "$meta" ;;
    completed|failed) sedi "s/\"completed\": *[^,]*/\"completed\": \"$(now_iso)\"/" "$meta" ;;
    queued)
      local count
      count=$(grep -o '"retry_count": *[0-9]*' "$meta" | grep -o '[0-9]*')
      count=$((count + 1))
      sedi "s/\"retry_count\": *[0-9]*/\"retry_count\": $count/" "$meta"
      [ -n "$extra_value" ] && sedi "s/\"queued_reason\": *[^,}]*/\"queued_reason\": \"$extra_value\"/" "$meta"
      ;;
  esac
  if [ -n "$extra_field" ] && [ "$new_status" != "queued" ]; then
    sedi "s/\"$extra_field\": *[^,}]*/\"$extra_field\": \"$extra_value\"/" "$meta"
  fi
  local task_id
  task_id=$(basename "$dir" | cut -d_ -f1)
  echo "{\"ts\":\"$(now_iso)\",\"id\":\"$task_id\",\"event\":\"$new_status\",\"detail\":\"\"}" >> "${ACTIVITY_LOG:-/dev/null}"
}

read_meta_field() {
  local meta="$1" field="$2"
  grep -o "\"$field\": *\"[^\"]*\"" "$meta" 2>/dev/null | sed 's/.*: *"\([^"]*\)"/\1/' || echo ""
}

read_meta_field_raw() {
  local meta="$1" field="$2"
  grep -o "\"$field\": *[^,}]*" "$meta" 2>/dev/null | sed 's/.*: *//' | tr -d '"' || echo ""
}

log_activity() {
  local id="$1" event="$2" detail="${3:-}"
  echo "{\"ts\":\"$(now_iso)\",\"id\":\"$id\",\"event\":\"$event\",\"detail\":\"$detail\"}" >> "${ACTIVITY_LOG:-/dev/null}"
}

assert_equals() {
  local expected="$1" actual="$2" msg="${3:-expected '$1' got '$2'}"
  assert_eq "$expected" "$actual" "$msg"
}

assert_file_contains() {
  local path="$1" needle="$2" msg="${3:-file '$1' does not contain '$2'}"
  if [ -f "$path" ] && grep -qF "$needle" "$path"; then
    pass
  else
    fail "$msg"
  fi
}

end_test() {
  print_summary "${CURRENT_TEST:-Tests}"
  [ "$TESTS_FAILED" -eq 0 ]
}

print_summary() {
  local suite_name="${1:-Tests}"
  echo ""
  echo "========================================"
  printf " ${suite_name}: "
  if [ "$TESTS_FAILED" -eq 0 ]; then
    printf "${GREEN}%d/%d passed${NC}\n" "$TESTS_PASSED" "$TESTS_TOTAL"
  else
    printf "${RED}%d/%d passed (%d failed)${NC}\n" "$TESTS_PASSED" "$TESTS_TOTAL" "$TESTS_FAILED"
  fi
  echo "========================================"
  return "$TESTS_FAILED"
}
