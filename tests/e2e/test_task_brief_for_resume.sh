#!/usr/bin/env bash
# test_task_brief_for_resume.sh — Test that the task brief is correctly handled during resume

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"

echo "=== test_task_brief_for_resume (E2E) ==="

# Test 1: Resume processes task with correct brief
setup_e2e_env
start_test "resume: task brief is correctly processed during resume"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_GEMINI_BEHAVIOR=success
create_mock_queue_entry "T001" "my_task_name" "pending" "gemini" "This is a custom task brief for testing purposes."

output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --resume 2>&1)
assert_contains "$output" "[RESUME] Re-dispatching T001 (my_task_name) to gemini"
assert_contains "$output" "Received prompt: This is a custom task brief for testing purposes."
assert_contains "$output" "DONE"
teardown_test_env

print_summary "task_brief_for_resume (E2E)"
