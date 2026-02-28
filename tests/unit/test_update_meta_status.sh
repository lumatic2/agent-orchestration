#!/usr/bin/env bash
# test_update_meta_status.sh — 6 tests for update_meta_status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"
source "$SCRIPT_DIR/lib/source_functions.sh"

source_orchestrate_functions

echo "=== test_update_meta_status ==="

setup_test_env

# Create a base queue entry
DIR=$(create_mock_queue_entry "T001" "test_task" "pending" "gemini")
META="$DIR/meta.json"

# Test 1: Update to dispatched
start_test "update_meta_status: pending → dispatched"
update_meta_status "$DIR" "dispatched"
status=$(read_meta_field "$META" "status")
assert_eq "dispatched" "$status"

# Test 2: dispatched sets dispatched timestamp
start_test "update_meta_status: dispatched sets timestamp"
dispatched=$(read_meta_field "$META" "dispatched")
assert_neq "" "$dispatched" "dispatched timestamp should not be empty"

# Test 3: Update to completed
start_test "update_meta_status: dispatched → completed"
update_meta_status "$DIR" "completed"
status=$(read_meta_field "$META" "status")
assert_eq "completed" "$status"

# Test 4: completed sets completed timestamp
start_test "update_meta_status: completed sets timestamp"
completed=$(read_meta_field "$META" "completed")
assert_neq "" "$completed" "completed timestamp should not be empty"

teardown_test_env

# Test 5: queued increments retry_count
setup_test_env
DIR=$(create_mock_queue_entry "T002" "retry_task" "pending" "codex")
META="$DIR/meta.json"

start_test "update_meta_status: queued increments retry_count"
update_meta_status "$DIR" "queued" "queued_reason" "rate_limited"
retries=$(read_meta_field_raw "$META" "retry_count")
assert_eq "1" "$retries"

# Test 6: queued sets queued_reason
start_test "update_meta_status: queued sets queued_reason"
reason=$(read_meta_field "$META" "queued_reason")
assert_eq "rate_limited" "$reason"

teardown_test_env
print_summary "update_meta_status"
