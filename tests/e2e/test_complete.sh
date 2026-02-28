#!/usr/bin/env bash
# test_complete.sh — 5 tests: --complete manual completion + error cases

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"
source "$SCRIPT_DIR/lib/source_functions.sh"

echo "=== test_complete (E2E) ==="

# Test 1: Complete marks task as completed
setup_e2e_env
start_test "complete: marks task as completed"
create_mock_queue_entry "T001" "complete_test" "dispatched" "gemini"
bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --complete T001 "Done manually" 2>&1 > /dev/null
status=$(grep -o '"status": *"[^"]*"' "$QUEUE_DIR/T001_complete_test/meta.json" | sed 's/.*: *"\([^"]*\)"/\1/')
assert_eq "completed" "$status"
teardown_test_env

# Test 2: Complete creates result.md
setup_e2e_env
start_test "complete: creates result.md with summary"
create_mock_queue_entry "T001" "result_test" "pending" "codex"
bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --complete T001 "My summary" 2>&1 > /dev/null
result_content=$(cat "$QUEUE_DIR/T001_result_test/result.md" 2>/dev/null)
assert_eq "My summary" "$result_content"
teardown_test_env

# Test 3: Complete outputs success message
setup_e2e_env
start_test "complete: outputs COMPLETE message"
create_mock_queue_entry "T001" "msg_test" "pending" "gemini"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --complete T001 "Done" 2>&1)
assert_contains "$output" "[COMPLETE]"
teardown_test_env

# Test 4: Complete nonexistent task → error
setup_e2e_env
start_test "complete: nonexistent task returns error"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --complete T999 "Nope" 2>&1) || true
assert_contains "$output" "not found"
teardown_test_env

# Test 5: Complete with default summary
setup_e2e_env
start_test "complete: default summary when none provided"
create_mock_queue_entry "T001" "default_test" "dispatched" "codex"
bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --complete T001 2>&1 > /dev/null
result_content=$(cat "$QUEUE_DIR/T001_default_test/result.md" 2>/dev/null)
assert_eq "Manually completed" "$result_content"
teardown_test_env

print_summary "complete (E2E)"
