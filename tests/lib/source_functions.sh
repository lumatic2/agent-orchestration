#!/usr/bin/env bash
# source_functions.sh — Extract and source functions from orchestrate.sh
# Avoids executing top-level code (set -euo, mkdir, case dispatch)

TESTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(dirname "$TESTS_LIB_DIR")"
REPO_ROOT="$(dirname "$TESTS_DIR")"
ORCHESTRATE_SH="$REPO_ROOT/scripts/orchestrate.sh"

# Copy orchestrate.sh, neutralize top-level execution, then source it.
# Preserves all functions (including those with heredocs) correctly.
source_orchestrate_functions() {
  local temp_func_file
  temp_func_file=$(mktemp)

  # Neutralize only non-function top-level code
  sed \
    -e 's/^set -euo pipefail/# [neutralized] set -euo pipefail/' \
    -e 's|^source "\$SCRIPT_DIR/env.sh"|# [neutralized] source "$SCRIPT_DIR/env.sh"|' \
    -e 's/^mkdir -p /# [neutralized] mkdir -p /' \
    -e 's/^TIMESTAMP=.*/# [neutralized] TIMESTAMP/' \
    -e 's/^ISO_NOW=.*/# [neutralized] ISO_NOW/' \
    -e '/^case "\${1:-}" in$/,/^esac$/ s/^/# [neutralized] /' \
    -e '/^if \[\[ "\${1:-}" == "--brief" \]\]/,/^fi$/ s/^/# [neutralized] /' \
    -e '/^AGENT="\${1:?/,/^echo "\[QUEUE\]/ s/^/# [neutralized] /' \
    -e '/^# --- Main dispatch ---$/,/^esac$/ s/^/# [neutralized] /' \
    -e '/^echo ""$/,$ s/^/# [neutralized] /' \
    "$ORCHESTRATE_SH" > "$temp_func_file"

  # Save and restore test env vars that sourcing might overwrite
  local saved_queue_dir="${QUEUE_DIR:-}"
  local saved_log_dir="${LOG_DIR:-}"
  local saved_repo_dir="${REPO_DIR:-}"
  local saved_activity_log="${ACTIVITY_LOG:-}"
  local saved_iso_now="${ISO_NOW:-}"
  local saved_timestamp="${TIMESTAMP:-}"

  source "$temp_func_file"

  # Restore test env vars
  [ -n "$saved_queue_dir" ] && QUEUE_DIR="$saved_queue_dir"
  [ -n "$saved_log_dir" ] && LOG_DIR="$saved_log_dir"
  [ -n "$saved_repo_dir" ] && REPO_DIR="$saved_repo_dir"
  [ -n "$saved_activity_log" ] && ACTIVITY_LOG="$saved_activity_log"
  [ -n "$saved_iso_now" ] && ISO_NOW="$saved_iso_now"
  [ -n "$saved_timestamp" ] && TIMESTAMP="$saved_timestamp"

  rm -f "$temp_func_file"
}

# Source guard.sh for testing (it expects $1 as input, so we wrap it)
run_guard() {
  local input="$1"
  bash "$REPO_ROOT/scripts/guard.sh" "$input" 2>&1
  return $?
}
