#!/usr/bin/env bash
# run_tests.sh — Main test runner: executes all unit + E2E tests and prints summary
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
FAILED_NAMES=()

run_suite() {
  local test_file="$1"
  local suite_name
  suite_name=$(basename "$test_file" .sh)
  TOTAL_SUITES=$((TOTAL_SUITES + 1))

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " Running: $suite_name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if bash "$test_file"; then
    PASSED_SUITES=$((PASSED_SUITES + 1))
  else
    FAILED_SUITES=$((FAILED_SUITES + 1))
    FAILED_NAMES+=("$suite_name")
  fi
}

echo "╔══════════════════════════════════════════╗"
echo "║   Agent Orchestration Test Suite         ║"
echo "╚══════════════════════════════════════════╝"

# --- Unit Tests ---
echo ""
printf "${YELLOW}▶ UNIT TESTS${NC}\n"
for f in "$TESTS_DIR"/unit/test_*.sh; do
  [ -f "$f" ] && run_suite "$f"
done

# --- E2E Tests ---
echo ""
printf "${YELLOW}▶ E2E TESTS${NC}\n"
for f in "$TESTS_DIR"/e2e/test_*.sh; do
  [ -f "$f" ] && run_suite "$f"
done

# --- Final Summary ---
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║             FINAL SUMMARY                ║"
echo "╠══════════════════════════════════════════╣"
printf "║  Suites: %d total, " "$TOTAL_SUITES"
printf "${GREEN}%d passed${NC}, " "$PASSED_SUITES"
if [ "$FAILED_SUITES" -gt 0 ]; then
  printf "${RED}%d failed${NC}" "$FAILED_SUITES"
else
  printf "0 failed"
fi
echo "       ║"
echo "╚══════════════════════════════════════════╝"

if [ "$FAILED_SUITES" -gt 0 ]; then
  echo ""
  printf "${RED}Failed suites:${NC}\n"
  for name in "${FAILED_NAMES[@]}"; do
    echo "  ✗ $name"
  done
  exit 1
fi

printf "${GREEN}All suites passed!${NC}\n"
exit 0
