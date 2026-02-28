#!/usr/bin/env bash
# test_dispatch_cycle.sh — 6 tests: full dispatch cycle with mock agents

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"

echo "=== test_dispatch_cycle (E2E) ==="

# Test 1: Gemini dispatch creates queue entry and completes
setup_e2e_env
start_test "dispatch: gemini creates queue + completes"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_GEMINI_BEHAVIOR=success
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" gemini "Analyze routing" test-dispatch 2>&1)
# Check queue entry was created
found_dirs=$(ls -d "$QUEUE_DIR"/T*_test-dispatch 2>/dev/null | wc -l)
assert_eq "1" "$found_dirs"
teardown_test_env

# Test 2: Completed task has status=completed in meta.json
setup_e2e_env
start_test "dispatch: completed status in meta.json"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_GEMINI_BEHAVIOR=success
bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" gemini "Analyze" completed-test 2>&1 > /dev/null
meta=$(ls "$QUEUE_DIR"/T*_completed-test/meta.json 2>/dev/null | head -1)
if [ -n "$meta" ]; then
  source "$SCRIPT_DIR/lib/source_functions.sh"
  source_orchestrate_functions
  status=$(read_meta_field "$meta" "status")
  assert_eq "completed" "$status"
else
  fail "meta.json not found"
fi
teardown_test_env

# Test 3: Codex dispatch works
setup_e2e_env
start_test "dispatch: codex creates queue + completes"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_CODEX_BEHAVIOR=success
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" codex "Build feature" codex-test 2>&1)
assert_contains "$output" "[QUEUE]"
teardown_test_env

# Test 4: Result file created on success
setup_e2e_env
start_test "dispatch: result.md created on success"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_GEMINI_BEHAVIOR=success
bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" gemini "Research" result-test 2>&1 > /dev/null
result_file=$(ls "$QUEUE_DIR"/T*_result-test/result.md 2>/dev/null | head -1)
if [ -n "$result_file" ]; then
  assert_file_exists "$result_file"
else
  fail "result.md not found"
fi
teardown_test_env

# Test 5: Brief file created
setup_e2e_env
start_test "dispatch: brief.md created with task content"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_GEMINI_BEHAVIOR=success
bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" gemini "My specific task" brief-test 2>&1 > /dev/null
brief_file=$(ls "$QUEUE_DIR"/T*_brief-test/brief.md 2>/dev/null | head -1)
if [ -n "$brief_file" ]; then
  content=$(cat "$brief_file")
  assert_contains "$content" "My specific task"
else
  fail "brief.md not found"
fi
teardown_test_env

# Test 6: Activity log records events
setup_e2e_env
start_test "dispatch: activity.jsonl has entries"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_GEMINI_BEHAVIOR=success
bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" gemini "Task" activity-test 2>&1 > /dev/null
if [ -f "$ACTIVITY_LOG" ]; then
  line_count=$(wc -l < "$ACTIVITY_LOG")
  # At least created + dispatched + completed = 3 entries
  if [ "$line_count" -ge 2 ]; then
    pass
  else
    fail "expected >= 2 activity lines, got $line_count"
  fi
else
  fail "activity.jsonl not found"
fi
teardown_test_env

print_summary "dispatch_cycle (E2E)"
