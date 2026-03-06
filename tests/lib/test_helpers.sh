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

assert_matches() {
  local haystack="$1" pattern="$2"
  if echo "$haystack" | grep -qE "$pattern"; then
    pass
  else
    fail "output does not match pattern '$pattern'"
  fi
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
