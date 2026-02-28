#!/usr/bin/env bash
# test_log_activity.sh — 3 tests for log_activity

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"
source "$SCRIPT_DIR/lib/source_functions.sh"

source_orchestrate_functions

echo "=== test_log_activity ==="

setup_test_env

# Test 1: Basic log entry is appended
start_test "log_activity: appends JSON line"
log_activity "T001" "created" "agent=gemini"
result=$(cat "$ACTIVITY_LOG")
assert_contains "$result" '"id":"T001"'

# Test 2: Event field is correct
start_test "log_activity: event field correct"
assert_contains "$result" '"event":"created"'

# Test 3: Multiple entries append (not overwrite)
start_test "log_activity: multiple entries append"
log_activity "T002" "dispatched" ""
line_count=$(wc -l < "$ACTIVITY_LOG")
assert_eq "2" "$line_count"

teardown_test_env
print_summary "log_activity"
