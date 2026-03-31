#!/bin/bash
# gemini-vault.sh — cron용 Gemini 리서치 → vault 저장
# Usage: bash gemini-vault.sh "task" "slug" [domain]
# domain 기본값: research

set -euo pipefail

TASK="${1:?Usage: gemini-vault.sh \"task\" \"slug\" [domain]}"
SLUG="${2:?slug required}"
DOMAIN="${3:-research}"
DATE=$(date +%Y-%m-%d)
VAULT_DIR="$HOME/vault/10-knowledge/${DOMAIN}"
VAULT_FILE="${VAULT_DIR}/${SLUG}_${DATE}.md"
LOG_FILE="$HOME/projects/agent-orchestration/logs/${SLUG}.log"

# nvm PATH (M4 비대화형 셸)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh" --no-use
[ -s "$NVM_DIR/alias/default" ] && nvm use "$(cat "$NVM_DIR/alias/default")" 2>/dev/null || true

# gemini 바이너리 찾기
GEMINI_BIN=$(which gemini 2>/dev/null || ls "$NVM_DIR"/versions/node/*/bin/gemini 2>/dev/null | tail -1 || echo "")
if [ -z "$GEMINI_BIN" ]; then
  echo "[ERROR] gemini not found" | tee -a "$LOG_FILE"
  exit 1
fi

echo "[START] $SLUG @ $DATE" | tee -a "$LOG_FILE"
echo "[TASK] $TASK" | tee -a "$LOG_FILE"

# Gemini 실행
RESULT=$("$GEMINI_BIN" -p "$TASK" 2>&1 \
  | grep -Ev "YOLO mode is enabled|All tool calls will be automatically approved|Loaded cached credentials|\[WARN\]|EPERM|EACCES" \
  || true)

# 메타 응답 감지 (너무 짧거나 "I have completed" 류)
CLEAN_LEN=$(echo "$RESULT" | grep -v "^$" | wc -c)
if [ "$CLEAN_LEN" -lt 300 ]; then
  echo "[WARN] Meta-response detected. Retrying..." | tee -a "$LOG_FILE"
  RETRY_PROMPT="IMPORTANT: Output the full analysis content directly. Do NOT say 'I completed' or 'analysis is done'. Write everything inline now.

${TASK}"
  RESULT=$("$GEMINI_BIN" -p "$RETRY_PROMPT" 2>&1 \
    | grep -Ev "YOLO mode is enabled|All tool calls will be automatically approved|Loaded cached credentials|\[WARN\]|EPERM|EACCES" \
    || true)
fi

# vault 저장
mkdir -p "$VAULT_DIR"
cat > "$VAULT_FILE" << VAULTEOF
---
type: knowledge
domain: ${DOMAIN}
source: gemini-cli
date: ${DATE}
status: inbox
task: ${SLUG}
---

${RESULT}
VAULTEOF

echo "[OK] Saved → $VAULT_FILE" | tee -a "$LOG_FILE"
