#!/usr/bin/env bash
# channel-watchdog.sh — claude-channel 세션 자동 복구 + !reset 처리
# Cron: * * * * * (매 10초 루프)

SESSION="claude-channel"
LOG="$HOME/projects/agent-orchestration/logs/channel-watchdog.log"
RESTART_SCRIPT="$HOME/projects/agent-orchestration/scripts/channel-restart.sh"
LOCK_FILE="/tmp/channel-restart.lock"

tmux has-session -t "$SESSION" 2>/dev/null || exit 0

CONTENT=$(tmux capture-pane -t "$SESSION" -p -S -5 2>/dev/null)

# 1) 인터랙티브 UI 감지 → Escape
if echo "$CONTENT" | grep -q "↑↓ to navigate\|Esc to cancel\|to confirm"; then
  tmux send-keys -t "$SESSION" Escape
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 인터랙티브 UI → Escape" >> "$LOG"
  exit 0
fi

# 2) !reset 감지 → 쿨다운 체크 후 재시작
if echo "$CONTENT" | grep -q "telegram.*!reset"; then
  # 60초 쿨다운: 마지막 재시작 후 60초 안 지났으면 스킵
  if [ -f "$LOCK_FILE" ]; then
    LAST=$(cat "$LOCK_FILE")
    NOW=$(date +%s)
    if [ $((NOW - LAST)) -lt 60 ]; then
      exit 0
    fi
  fi
  date +%s > "$LOCK_FILE"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] !reset 감지 → 재시작" >> "$LOG"
  bash "$RESTART_SCRIPT"
fi
