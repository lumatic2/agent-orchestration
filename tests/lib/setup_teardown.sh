#!/usr/bin/env bash
# setup_teardown.sh — Test isolation via temp directories

TEST_TEMP_DIR=""

setup_test_env() {
  TEST_TEMP_DIR=$(mktemp -d)
  mkdir -p "$TEST_TEMP_DIR/queue"
  mkdir -p "$TEST_TEMP_DIR/logs"
  mkdir -p "$TEST_TEMP_DIR/scripts"
  mkdir -p "$TEST_TEMP_DIR/templates"

  # Override globals used by orchestrate.sh functions
  export QUEUE_DIR="$TEST_TEMP_DIR/queue"
  export LOG_DIR="$TEST_TEMP_DIR/logs"
  export REPO_DIR="$TEST_TEMP_DIR"
  export ACTIVITY_LOG="$QUEUE_DIR/activity.jsonl"
  export ISO_NOW="2026-02-28T10:00:00+0900"
  export TIMESTAMP="20260228_100000"

  touch "$ACTIVITY_LOG"
}

teardown_test_env() {
  if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
  TEST_TEMP_DIR=""
}

# Setup E2E env with symlinks to real scripts
setup_e2e_env() {
  setup_test_env

  local real_repo
  real_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

  # Symlink real scripts (cp for Windows Git Bash compat)
  cp "$real_repo/scripts/orchestrate.sh" "$TEST_TEMP_DIR/scripts/orchestrate.sh"
  cp "$real_repo/scripts/guard.sh" "$TEST_TEMP_DIR/scripts/guard.sh"

  # Copy templates if they exist
  if [ -d "$real_repo/templates" ]; then
    cp -r "$real_repo/templates/"* "$TEST_TEMP_DIR/templates/" 2>/dev/null || true
  fi
}

# Create a mock queue entry for testing
create_mock_queue_entry() {
  local id="$1" name="$2" status="${3:-pending}" agent="${4:-gemini}" brief_content="${5:-Test task brief for $name}"
  local dir="$QUEUE_DIR/${id}_${name}"
  mkdir -p "$dir"

  cat > "$dir/meta.json" << EOF
{
  "id": "$id",
  "name": "$name",
  "status": "$status",
  "agent": "$agent",
  "model": "",
  "created": "2026-02-28T09:00:00+0900",
  "dispatched": null,
  "completed": null,
  "exit_code": null,
  "log_file": null,
  "retry_count": 0,
  "queued_reason": null
}
EOF

  echo "$brief_content" > "$dir/brief.md"
  MOCK_QUEUE_DIR="$dir"
}
