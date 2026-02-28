#!/usr/bin/env bash
# test_parse_codex_result.sh — 5 tests for parse_codex_result

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"
source "$SCRIPT_DIR/lib/source_functions.sh"

source_orchestrate_functions

echo "=== test_parse_codex_result ==="

setup_test_env

# Test 1: Extracts agent_message text
start_test "parse_codex_result: extracts agent message"
input='{"type":"agent_message","text":"Files updated successfully."}'
result=$(parse_codex_result "$input")
assert_contains "$result" "Files updated successfully."

# Test 2: Extracts token usage
start_test "parse_codex_result: extracts token usage"
input='{"type":"agent_message","text":"Done."}
{"type":"turn.completed","usage":{"input_tokens":100,"output_tokens":50}}'
result=$(parse_codex_result "$input")
assert_contains "$result" "Token Usage"

# Test 3: Multiple agent messages — takes last one
start_test "parse_codex_result: takes last agent message"
input='{"type":"agent_message","text":"First message"}
{"type":"agent_message","text":"Final summary here"}'
result=$(parse_codex_result "$input")
assert_contains "$result" "Final summary here"

# Test 4: No agent_message — no crash
start_test "parse_codex_result: no agent_message no crash"
input='{"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":5}}'
result=$(parse_codex_result "$input")
# Should not contain "Codex Summary" section if no agent_message
assert_not_contains "$result" "Codex Summary"

# Test 5: Empty input — no crash
start_test "parse_codex_result: empty input no crash"
result=$(parse_codex_result "")
assert_eq "" "$result"

teardown_test_env
print_summary "parse_codex_result"
