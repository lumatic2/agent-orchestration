#!/usr/bin/env bash
#
# Test: "$REPO_DIR/scripts/orchestrate.sh" --resume functionality
#
# Ensures that `"$REPO_DIR/scripts/orchestrate.sh" --resume` correctly identifies and
# re-dispatches the oldest pending/queued task, and updates its status.
# It also verifies that only one task is processed at a time.

set -euo pipefail

# Dummy declarations for global variables that will be set by setup_test_env
# This prevents "unbound variable" errors when helper functions are sourced/defined early.
REPO_DIR=""
QUEUE_DIR=""
ACTIVITY_LOG=""

# Source the test helpers
source "$(dirname "${BASH_SOURCE[0]}")/../lib/setup_teardown.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/test_helpers.sh"

# Helper functions provided by test_helpers.sh (sedi, now_iso, update_meta_status, etc.)

# Get the ID of the most recently created task
get_last_task_id() {
  local last_id=""
  for dir in "$QUEUE_DIR"/T[0-9][0-9][0-9]_*/; do
    [ -d "$dir" ] || continue
    local dirname
    dirname="$(basename "$dir")"
    local id="${dirname%%_*}" # Extract Txxx part
    if [[ -z "$last_id" || "$id" > "$last_id" ]]; then
      last_id="$id"
    fi
  done
  echo "$last_id"
}

setup_mocks() {
  MOCK_CODEX_BIN="$REPO_DIR/tests/mocks/codex"
  MOCK_GEMINI_BIN="$REPO_DIR/tests/mocks/gemini"

  mkdir -p "$MOCK_CODEX_BIN" "$MOCK_GEMINI_BIN"

  # Mock codex to succeed
  cat << 'EOF' > "$MOCK_CODEX_BIN/codex"
#!/usr/bin/env bash
echo "MOCK CODEX: Task executed successfully."
echo '{"type":"agent_message","text":"mocked codex output"}'
echo '{"type":"turn.completed","usage":{"prompt_tokens":10,"completion_tokens":20}}'
exit 0
EOF
  chmod +x "$MOCK_CODEX_BIN/codex"

  # Mock gemini to succeed
  cat << 'EOF' > "$MOCK_GEMINI_BIN/gemini"
#!/usr/bin/env bash
echo "MOCK GEMINI: Task executed successfully."
echo "mocked gemini output" > "$1" # log_file path is passed as "$1" when using > "$log_file" 2>&1
exit 0
EOF
  chmod +x "$MOCK_GEMINI_BIN/gemini"

  # Override PATH to use our mocks
  export PATH="$MOCK_CODEX_BIN:$MOCK_GEMINI_BIN:$PATH"
}

start_test "$REPO_DIR/scripts/orchestrate.sh --resume functionality"

# --- Test Setup ---
# Create temporary queue directory
setup_e2e_env
setup_mocks

# 1. Create a "completed" task (should be ignored by --resume)
"$REPO_DIR/scripts/orchestrate.sh" codex "completed task brief" "completed-task"
sleep 0.1 # Ensure unique timestamps for sorting
TASK_COMPLETED_ID=$(get_last_task_id)
assert_not_empty "$TASK_COMPLETED_ID" "completed task ID should not be empty"
update_meta_status "$QUEUE_DIR/${TASK_COMPLETED_ID}_completed-task" "completed"
log_info "Created completed task: $TASK_COMPLETED_ID"

# 2. Create a "pending" task (should be resumed first)
"$REPO_DIR/scripts/orchestrate.sh" codex "pending task brief" "pending-task"
sleep 0.1 # Ensure unique timestamps for sorting
TASK_PENDING_ID=$(get_last_task_id)
assert_not_empty "$TASK_PENDING_ID" "pending task ID should not be empty"
# Initially it's dispatched, we need to set it back to pending for the test
update_meta_status "$QUEUE_DIR/${TASK_PENDING_ID}_pending-task" "pending"
log_info "Created pending task: $TASK_PENDING_ID"

# 3. Create another "queued" task (should be resumed second, if at all)
"$REPO_DIR/scripts/orchestrate.sh" gemini "another queued task brief" "another-queued-task"
sleep 0.1 # Ensure unique timestamps for sorting
TASK_QUEUED_ID=$(get_last_task_id)
assert_not_empty "$TASK_QUEUED_ID" "queued task ID should not be empty"
update_meta_status "$QUEUE_DIR/${TASK_QUEUED_ID}_another-queued-task" "queued" "queued_reason" "mock_rate_limit"
log_info "Created queued task: $TASK_QUEUED_ID"

# --- Test Execution ---

# Run --resume. It should pick up TASK_PENDING_ID
log_info "Running "$REPO_DIR/scripts/orchestrate.sh" --resume"
"$REPO_DIR/scripts/orchestrate.sh" --resume

# --- Test Assertions ---

# Verify that TASK_PENDING_ID was processed and is now "completed"
PENDING_TASK_DIR="$QUEUE_DIR/${TASK_PENDING_ID}_pending-task"
PENDING_TASK_STATUS=$(read_meta_field "$PENDING_TASK_DIR/meta.json" "status")
assert_equals "completed" "$PENDING_TASK_STATUS" "Pending task should be completed after resume"
log_info "Status of $TASK_PENDING_ID: $PENDING_TASK_STATUS"

# Verify that TASK_QUEUED_ID (the second task) is still "queued"
# because --resume exits after the first one.
QUEUED_TASK_DIR="$QUEUE_DIR/${TASK_QUEUED_ID}_another-queued-task"
QUEUED_TASK_STATUS=$(read_meta_field "$QUEUED_TASK_DIR/meta.json" "status")
assert_equals "queued" "$QUEUED_TASK_STATUS" "Second queued task should still be queued"
log_info "Status of $TASK_QUEUED_ID: $QUEUED_TASK_STATUS"

# Verify that TASK_COMPLETED_ID is still "completed"
COMPLETED_TASK_DIR="$QUEUE_DIR/${TASK_COMPLETED_ID}_completed-task"
COMPLETED_TASK_STATUS=$(read_meta_field "$COMPLETED_TASK_DIR/meta.json" "status")
assert_equals "completed" "$COMPLETED_TASK_STATUS" "Completed task should remain completed"
log_info "Status of $TASK_COMPLETED_ID: $COMPLETED_TASK_STATUS"

# Verify mock codex output in result.md
assert_file_contains "$PENDING_TASK_DIR/result.md" "mocked codex output" "Result file should contain mock codex output"

end_test