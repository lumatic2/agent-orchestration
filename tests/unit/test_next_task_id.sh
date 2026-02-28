#!/usr/bin/env bash
# test_next_task_id.sh — 5 tests for next_task_id

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"
source "$SCRIPT_DIR/lib/source_functions.sh"

source_orchestrate_functions

echo "=== test_next_task_id ==="

# Test 1: Empty queue → T001
setup_test_env
start_test "next_task_id: empty queue returns T001"
result=$(next_task_id)
assert_eq "T001" "$result"
teardown_test_env

# Test 2: One task exists → T002
setup_test_env
start_test "next_task_id: one task → T002"
mkdir -p "$QUEUE_DIR/T001_test"
result=$(next_task_id)
assert_eq "T002" "$result"
teardown_test_env

# Test 3: Multiple tasks → next sequential
setup_test_env
start_test "next_task_id: T001+T002+T003 → T004"
mkdir -p "$QUEUE_DIR/T001_first"
mkdir -p "$QUEUE_DIR/T002_second"
mkdir -p "$QUEUE_DIR/T003_third"
result=$(next_task_id)
assert_eq "T004" "$result"
teardown_test_env

# Test 4: Gap in sequence — uses max+1, not fill gap
setup_test_env
start_test "next_task_id: gap T001+T005 → T006"
mkdir -p "$QUEUE_DIR/T001_first"
mkdir -p "$QUEUE_DIR/T005_fifth"
result=$(next_task_id)
assert_eq "T006" "$result"
teardown_test_env

# Test 5: Double digit — T010 exists
setup_test_env
start_test "next_task_id: T010 → T011"
mkdir -p "$QUEUE_DIR/T010_tenth"
result=$(next_task_id)
assert_eq "T011" "$result"
teardown_test_env

print_summary "next_task_id"
