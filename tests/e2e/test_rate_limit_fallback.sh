#!/usr/bin/env bash
# test_rate_limit_fallback.sh — 5 tests: rate limit detection + fallback chain

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"

echo "=== test_rate_limit_fallback (E2E) ==="

# Test 1: Gemini rate limit detected, task queued
setup_e2e_env
start_test "fallback: gemini rate limit queues task"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_GEMINI_BEHAVIOR=rate_limit
export MOCK_CODEX_BEHAVIOR=rate_limit
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" gemini "Research task" rl-test 2>&1) || true
assert_contains "$output" "RATE_LIMIT"
teardown_test_env

# Test 2: Codex rate limit triggers fallback to gemini
setup_e2e_env
start_test "fallback: codex rate limit triggers fallback"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_CODEX_BEHAVIOR=rate_limit
export MOCK_GEMINI_BEHAVIOR=success
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" codex "Code task" fallback-test 2>&1) || true
assert_contains "$output" "FALLBACK"
teardown_test_env

# Test 3: Both agents rate limited → queued
setup_e2e_env
start_test "fallback: both rate limited → queued"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_CODEX_BEHAVIOR=rate_limit
export MOCK_GEMINI_BEHAVIOR=rate_limit
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" codex-fallback "Task" both-rl 2>&1) || true
assert_contains "$output" "QUEUED"
teardown_test_env

# Test 4: Rate limited task gets queued_reason in meta
setup_e2e_env
start_test "fallback: queued_reason set in meta.json"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_GEMINI_BEHAVIOR=rate_limit
export MOCK_CODEX_BEHAVIOR=rate_limit
bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" gemini-fallback "Task" reason-test 2>&1 > /dev/null || true
meta=$(ls "$QUEUE_DIR"/T*_reason-test/meta.json 2>/dev/null | head -1)
if [ -n "$meta" ]; then
  reason=$(grep -o '"queued_reason": *"[^"]*"' "$meta" | sed 's/.*: *"\([^"]*\)"/\1/')
  if [ -n "$reason" ]; then pass; else fail "queued_reason is empty"; fi
else
  fail "meta.json not found"
fi
teardown_test_env

# Test 5: resource_exhausted also detected as rate limit
setup_e2e_env
start_test "fallback: resource_exhausted detected"
export PATH="$SCRIPT_DIR/mocks:$PATH"
export MOCK_GEMINI_BEHAVIOR=resource_exhausted
export MOCK_CODEX_BEHAVIOR=rate_limit
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" gemini "Task" exhaust-test 2>&1) || true
assert_contains "$output" "RATE_LIMIT"
teardown_test_env

print_summary "rate_limit_fallback (E2E)"
