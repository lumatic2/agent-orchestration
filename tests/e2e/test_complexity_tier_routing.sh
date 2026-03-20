#!/usr/bin/env bash
# test_complexity_tier_routing.sh — dry-run routing checks for all complexity tiers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/setup_teardown.sh"

echo "=== test_complexity_tier_routing (E2E) ==="

# Test 1: low tier -> codex light
setup_e2e_env
start_test "routing: low brief selects codex light"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --dry-run codex "1-3 files, <10 lines, simple edit, 단순 수정" low-tier 2>&1)
if echo "$output" | grep -qF "Tier:    low" \
  && echo "$output" | grep -qF "Model:   gpt-5.3-codex-spark" \
  && echo "$output" | grep -qF "Reason:  high"
then
  pass
else
  fail "unexpected low-tier routing output"
fi
teardown_test_env

# Test 2: medium tier -> codex heavy
setup_e2e_env
start_test "routing: medium brief selects codex heavy"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --dry-run codex "3-5 files, new feature, standard coding" medium-tier 2>&1)
if echo "$output" | grep -qF "Tier:    medium" \
  && echo "$output" | grep -qF "Model:   gpt-5.3-codex" \
  && echo "$output" | grep -qF "Reason:  xhigh"
then
  pass
else
  fail "unexpected medium-tier routing output"
fi
teardown_test_env

# Test 3: high tier -> chatgpt graceful fallback from missing ultra model to heavy
setup_e2e_env
start_test "routing: high brief falls back to chatgpt heavy"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --dry-run chatgpt "5+ files, complex bug with unclear root cause, non-trivial refactor" high-tier 2>&1)
if echo "$output" | grep -qF "Tier:    high" \
  && echo "$output" | grep -qF "Model:   gpt-5.2" \
  && echo "$output" | grep -qF "Reason:  xhigh" \
  && echo "$output" | grep -qF "[ROUTER] profile_source=complexity-fallback"
then
  pass
else
  fail "unexpected high-tier routing output"
fi
teardown_test_env

# Test 4: ultra tier -> gemini heavy
setup_e2e_env
start_test "routing: ultra brief selects gemini heavy"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --dry-run gemini "Full codebase analysis, architecture decisions, 신규 설계 패턴" ultra-tier 2>&1)
if echo "$output" | grep -qF "Tier:    ultra" \
  && echo "$output" | grep -qF "Model:   gemini-2.5-pro" \
  && echo "$output" | grep -qF "Reason:  auto"
then
  pass
else
  fail "unexpected ultra-tier routing output"
fi
teardown_test_env

# Test 5: explicit tier override wins over heuristic keywords
setup_e2e_env
start_test "routing: explicit complexity_tier overrides heuristics"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --dry-run codex $'complexity_tier: low\n5+ files, complex bug with unclear root cause' forced-low 2>&1)
if echo "$output" | grep -qF "Tier:    low" \
  && echo "$output" | grep -qF "Model:   gpt-5.3-codex-spark"
then
  pass
else
  fail "explicit tier override did not win"
fi
teardown_test_env

# Test 6: explicit alias keeps legacy fixed tier for compatibility
setup_e2e_env
start_test "routing: codex-spark alias remains fixed"
output=$(bash "$TEST_TEMP_DIR/scripts/orchestrate.sh" --dry-run codex-spark "Full codebase analysis, architecture decisions" alias-tier 2>&1)
if echo "$output" | grep -qF "Tier:    ultra" \
  && echo "$output" | grep -qF "Model:   gpt-5.3-codex-spark" \
  && echo "$output" | grep -qF "[ROUTER] profile_source=legacy-alias"
then
  pass
else
  fail "alias compatibility broke"
fi
teardown_test_env

print_summary "complexity_tier_routing (E2E)"
