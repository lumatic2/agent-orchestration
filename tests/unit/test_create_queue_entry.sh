#!/usr/bin/env bash
# test_create_queue_entry.sh — 4 tests for create_queue_entry

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"
source "$SCRIPT_DIR/lib/source_functions.sh"

source_orchestrate_functions

echo "=== test_create_queue_entry ==="

setup_test_env

# Test 1: Creates directory
start_test "create_queue_entry: creates task directory"
create_queue_entry "T001" "my_task" "codex" "Build the feature"
assert_dir_exists "$QUEUE_DIR/T001_my_task"

# Test 2: meta.json created with correct status
start_test "create_queue_entry: meta.json has pending status"
status=$(read_meta_field "$QUEUE_DIR/T001_my_task/meta.json" "status")
assert_eq "pending" "$status"

# Test 3: brief.md contains task content
start_test "create_queue_entry: brief.md contains task"
content=$(cat "$QUEUE_DIR/T001_my_task/brief.md")
assert_eq "Build the feature" "$content"

# Test 4: Activity log records creation
start_test "create_queue_entry: activity log has created event"
log_content=$(cat "$ACTIVITY_LOG")
assert_contains "$log_content" '"event":"created"'

teardown_test_env
print_summary "create_queue_entry"
