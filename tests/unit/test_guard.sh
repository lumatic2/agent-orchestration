#!/usr/bin/env bash
# test_guard.sh — 22 tests for guard.sh (15 block + 7 allow)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/source_functions.sh"

GUARD="$REPO_ROOT/scripts/guard.sh"

echo "=== test_guard ==="

# Helper: run guard and capture exit code
run_guard_test() {
  bash "$GUARD" "$1" 2>&1
  return $?
}

# ==========================================
# BLOCK tests (should exit 1)
# ==========================================

# --- Destructive file operations ---
start_test "guard BLOCKS: rm -rf /"
run_guard_test "rm -rf /" > /dev/null 2>&1; assert_exit_code "1" "$?"

start_test "guard BLOCKS: rm -rf ~"
run_guard_test "rm -rf ~" > /dev/null 2>&1; assert_exit_code "1" "$?"

start_test "guard BLOCKS: rm -rf . (current dir)"
run_guard_test "rm -rf . " > /dev/null 2>&1; assert_exit_code "1" "$?"

start_test "guard BLOCKS: rmdir /"
run_guard_test "rmdir /" > /dev/null 2>&1; assert_exit_code "1" "$?"

# --- Dangerous git operations ---
start_test "guard BLOCKS: git push --force"
run_guard_test "git push --force origin main" > /dev/null 2>&1; assert_exit_code "1" "$?"

start_test "guard BLOCKS: git push -f"
run_guard_test "git push -f origin main" > /dev/null 2>&1; assert_exit_code "1" "$?"

start_test "guard BLOCKS: git reset --hard"
run_guard_test "git reset --hard HEAD~1" > /dev/null 2>&1; assert_exit_code "1" "$?"

start_test "guard BLOCKS: git clean -fd"
run_guard_test "git clean -fd" > /dev/null 2>&1; assert_exit_code "1" "$?"

# --- Sensitive file access ---
start_test "guard BLOCKS: .env access"
run_guard_test "cat .env" > /dev/null 2>&1; assert_exit_code "1" "$?"

start_test "guard BLOCKS: credentials file"
run_guard_test "cat credentials.json" > /dev/null 2>&1; assert_exit_code "1" "$?"

start_test "guard BLOCKS: private.key"
run_guard_test "cat private.key" > /dev/null 2>&1; assert_exit_code "1" "$?"

start_test "guard BLOCKS: id_rsa"
run_guard_test "cat ~/.ssh/id_rsa" > /dev/null 2>&1; assert_exit_code "1" "$?"

# --- Dangerous SQL ---
start_test "guard BLOCKS: DROP TABLE"
run_guard_test "mysql -e 'DROP TABLE users'" > /dev/null 2>&1; assert_exit_code "1" "$?"

start_test "guard BLOCKS: TRUNCATE TABLE"
run_guard_test "psql -c 'TRUNCATE TABLE orders'" > /dev/null 2>&1; assert_exit_code "1" "$?"

# --- System-wide package operations ---
start_test "guard BLOCKS: npm install -g"
run_guard_test "npm install -g typescript" > /dev/null 2>&1; assert_exit_code "1" "$?"

# ==========================================
# ALLOW tests (should exit 0)
# ==========================================

start_test "guard ALLOWS: git push (no force)"
run_guard_test "git push origin main" > /dev/null 2>&1; assert_exit_code "0" "$?"

start_test "guard ALLOWS: git commit"
run_guard_test "git commit -m 'fix: update'" > /dev/null 2>&1; assert_exit_code "0" "$?"

start_test "guard ALLOWS: npm install (local)"
run_guard_test "npm install express" > /dev/null 2>&1; assert_exit_code "0" "$?"

start_test "guard ALLOWS: rm single file"
run_guard_test "rm temp.txt" > /dev/null 2>&1; assert_exit_code "0" "$?"

start_test "guard ALLOWS: ls command"
run_guard_test "ls -la" > /dev/null 2>&1; assert_exit_code "0" "$?"

start_test "guard ALLOWS: cat normal file"
run_guard_test "cat README.md" > /dev/null 2>&1; assert_exit_code "0" "$?"

start_test "guard ALLOWS: pip install (no --system)"
run_guard_test "pip install requests" > /dev/null 2>&1; assert_exit_code "0" "$?"

print_summary "guard"
