#!/usr/bin/env bash
# test_read_meta_field.sh — 6 tests for read_meta_field and read_meta_field_raw

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"
source "$SCRIPT_DIR/lib/source_functions.sh"

source_orchestrate_functions

echo "=== test_read_meta_field ==="

setup_test_env

# Create a reference meta.json
META="$TEST_TEMP_DIR/meta.json"
cat > "$META" << 'EOF'
{
  "id": "T001",
  "name": "test_task",
  "status": "pending",
  "agent": "gemini",
  "model": "gemini-2.5-flash",
  "created": "2026-02-28T09:00:00+0900",
  "dispatched": null,
  "completed": null,
  "exit_code": null,
  "log_file": null,
  "retry_count": 0,
  "queued_reason": null
}
EOF

# Test 1: Read string field — id
start_test "read_meta_field: id"
result=$(read_meta_field "$META" "id")
assert_eq "T001" "$result"

# Test 2: Read string field — status
start_test "read_meta_field: status"
result=$(read_meta_field "$META" "status")
assert_eq "pending" "$result"

# Test 3: Read string field — agent
start_test "read_meta_field: agent"
result=$(read_meta_field "$META" "agent")
assert_eq "gemini" "$result"

# Test 4: Read null field returns empty
start_test "read_meta_field: null field returns empty"
result=$(read_meta_field "$META" "dispatched")
assert_eq "" "$result"

# Test 5: Read nonexistent field returns empty
start_test "read_meta_field: nonexistent field returns empty"
result=$(read_meta_field "$META" "nonexistent_field")
assert_eq "" "$result"

# Test 6: read_meta_field_raw reads numeric value
start_test "read_meta_field_raw: retry_count numeric"
result=$(read_meta_field_raw "$META" "retry_count")
assert_eq "0" "$result"

teardown_test_env
print_summary "read_meta_field"
