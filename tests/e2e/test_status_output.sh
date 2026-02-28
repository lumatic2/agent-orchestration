#!/usr/bin/env bash
# test_status_output.sh — 4 tests: --status table format verification

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"

echo "=== test_status_output (E2E) ==="

# Test 1: Header line present
setup_e2e_env
start_test "status: header line present"
create_mock_queue_entry "T001" "test_task" "pending" "gemini"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --status 2>&1)
assert_contains "$output" "ID"
teardown_test_env

# Test 2: Task appears in status
setup_e2e_env
start_test "status: task appears in output"
create_mock_queue_entry "T001" "my_task" "pending" "codex"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --status 2>&1)
assert_contains "$output" "my_task"
teardown_test_env

# Test 3: Multiple tasks listed
setup_e2e_env
start_test "status: multiple tasks listed"
create_mock_queue_entry "T001" "first_task" "completed" "gemini"
create_mock_queue_entry "T002" "second_task" "pending" "codex"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --status 2>&1)
assert_contains "$output" "second_task"
teardown_test_env

# Test 4: Status shows agent name
setup_e2e_env
start_test "status: agent name shown"
create_mock_queue_entry "T001" "agent_test" "pending" "gemini"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --status 2>&1)
assert_contains "$output" "gemini"
teardown_test_env

print_summary "status_output (E2E)"
