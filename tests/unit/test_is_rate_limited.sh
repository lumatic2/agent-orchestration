#!/usr/bin/env bash
# test_is_rate_limited.sh — 8 tests for is_rate_limited

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"
source "$SCRIPT_DIR/lib/source_functions.sh"

source_orchestrate_functions

echo "=== test_is_rate_limited ==="

setup_test_env

# Test 1: Detects "rate limit"
start_test "is_rate_limited: detects 'rate limit'"
is_rate_limited "Error: rate limit exceeded" && result=0 || result=1
assert_eq "0" "$result"

# Test 2: Detects "429"
start_test "is_rate_limited: detects '429'"
is_rate_limited "Error: 429 Too Many Requests" && result=0 || result=1
assert_eq "0" "$result"

# Test 3: Detects "quota exceeded"
start_test "is_rate_limited: detects 'quota exceeded'"
is_rate_limited "quota exceeded for model" && result=0 || result=1
assert_eq "0" "$result"

# Test 4: Detects "too many requests"
start_test "is_rate_limited: detects 'too many requests'"
is_rate_limited "Error: too many requests" && result=0 || result=1
assert_eq "0" "$result"

# Test 5: Detects "resource exhausted"
start_test "is_rate_limited: detects 'resource exhausted'"
is_rate_limited "Error: resource exhausted" && result=0 || result=1
assert_eq "0" "$result"

# Test 6: Normal success output — NOT rate limited
start_test "is_rate_limited: normal output not detected"
is_rate_limited "Task completed successfully" && result=0 || result=1
assert_eq "1" "$result"

# Test 7: Empty output — NOT rate limited
start_test "is_rate_limited: empty output not detected"
is_rate_limited "" && result=0 || result=1
assert_eq "1" "$result"

# Test 8: Case insensitive — "Rate Limit"
start_test "is_rate_limited: case insensitive"
is_rate_limited "Rate Limit Exceeded" && result=0 || result=1
assert_eq "0" "$result"

teardown_test_env
print_summary "is_rate_limited"
