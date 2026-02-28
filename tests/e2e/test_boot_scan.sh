#!/usr/bin/env bash
# test_boot_scan.sh — 5 tests: --boot scan output verification

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"

echo "=== test_boot_scan (E2E) ==="

# Test 1: Clean queue — no pending tasks
setup_e2e_env
start_test "boot: clean queue shows clean message"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --boot 2>&1)
assert_contains "$output" "clean"
teardown_test_env

# Test 2: Pending task shows in boot scan
setup_e2e_env
start_test "boot: pending task detected"
create_mock_queue_entry "T001" "pending_task" "pending" "gemini"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --boot 2>&1)
assert_contains "$output" "PENDING"
teardown_test_env

# Test 3: Stale dispatched task shows in boot scan
setup_e2e_env
start_test "boot: stale dispatched task detected"
create_mock_queue_entry "T001" "stale_task" "dispatched" "codex"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --boot 2>&1)
assert_contains "$output" "STALE"
teardown_test_env

# Test 4: Completed tasks are NOT shown
setup_e2e_env
start_test "boot: completed tasks not shown"
create_mock_queue_entry "T001" "done_task" "completed" "gemini"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --boot 2>&1)
assert_not_contains "$output" "done_task"
teardown_test_env

# Test 5: Mixed queue — correct count
setup_e2e_env
start_test "boot: mixed queue shows correct count"
create_mock_queue_entry "T001" "done" "completed" "gemini"
create_mock_queue_entry "T002" "pending_one" "pending" "codex"
create_mock_queue_entry "T003" "stale_one" "dispatched" "gemini"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --boot 2>&1)
assert_contains "$output" "2 task(s) need attention"
teardown_test_env

print_summary "boot_scan (E2E)"
