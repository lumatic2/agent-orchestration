#!/usr/bin/env bash
# test_resume.sh — 5 tests: --resume re-dispatches pending tasks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"

echo "=== test_resume (E2E) ==="

# Test 1: Resume finds pending task
setup_e2e_env
start_test "resume: finds and re-dispatches pending task"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_GEMINI_BEHAVIOR=success
create_mock_queue_entry "T001" "resume_test" "pending" "gemini"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --resume 2>&1)
assert_contains "$output" "RESUME"
teardown_test_env

# Test 2: Resume completes task on success
setup_e2e_env
start_test "resume: completes task on agent success"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_GEMINI_BEHAVIOR=success
create_mock_queue_entry "T001" "resume_ok" "pending" "gemini"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --resume 2>&1)
assert_contains "$output" "DONE"
teardown_test_env

# Test 3: Resume queues task on rate limit
setup_e2e_env
start_test "resume: queues task on rate limit"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_GEMINI_BEHAVIOR=rate_limit
create_mock_queue_entry "T001" "resume_rl" "pending" "gemini"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --resume 2>&1)
assert_contains "$output" "QUEUED"
teardown_test_env

# Test 4: Resume with empty queue
setup_e2e_env
start_test "resume: empty queue shows no tasks message"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --resume 2>&1)
assert_contains "$output" "No pending"
teardown_test_env

# Test 5: Resume picks oldest (first) pending task
setup_e2e_env
start_test "resume: picks first pending by directory order"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_CODEX_BEHAVIOR=success
create_mock_queue_entry "T001" "first_pending" "pending" "codex"
create_mock_queue_entry "T002" "second_pending" "pending" "codex"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --resume 2>&1)
assert_contains "$output" "T001"
teardown_test_env

print_summary "resume (E2E)"
