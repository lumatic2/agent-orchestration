#!/usr/bin/env bash
# test_queue_lifecycle.sh — 4 tests: pending → dispatched → completed state transitions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"
source "$SCRIPT_DIR/lib/source_functions.sh"

source_orchestrate_functions

echo "=== test_queue_lifecycle (E2E) ==="

# Test 1: New entry starts as pending
setup_test_env
start_test "lifecycle: new entry starts as pending"
create_queue_entry "T001" "lifecycle_test" "gemini" "Test task"
status=$(read_meta_field "$QUEUE_DIR/T001_lifecycle_test/meta.json" "status")
assert_eq "pending" "$status"
teardown_test_env

# Test 2: pending → dispatched
setup_test_env
start_test "lifecycle: pending → dispatched"
create_mock_queue_entry "T001" "lifecycle_test" "pending" "gemini"
DIR="$MOCK_QUEUE_DIR"
update_meta_status "$DIR" "dispatched"
status=$(read_meta_field "$DIR/meta.json" "status")
assert_eq "dispatched" "$status"
teardown_test_env

# Test 3: dispatched → completed
setup_test_env
start_test "lifecycle: dispatched → completed"
create_mock_queue_entry "T001" "lifecycle_test" "dispatched" "gemini"
DIR="$MOCK_QUEUE_DIR"
update_meta_status "$DIR" "completed"
status=$(read_meta_field "$DIR/meta.json" "status")
assert_eq "completed" "$status"
teardown_test_env

# Test 4: pending → queued (rate limited) → retry_count increments
setup_test_env
start_test "lifecycle: pending → queued increments retry"
create_mock_queue_entry "T001" "lifecycle_test" "pending" "codex"
DIR="$MOCK_QUEUE_DIR"
update_meta_status "$DIR" "queued" "queued_reason" "rate_limited"
update_meta_status "$DIR" "queued" "queued_reason" "rate_limited"
retries=$(read_meta_field_raw "$DIR/meta.json" "retry_count")
assert_eq "2" "$retries"
teardown_test_env

print_summary "queue_lifecycle (E2E)"
