#!/usr/bin/env bash
# channel-restart.sh — claude-channel tmux 세션 재시작

SESSION="claude-channel"
LOG="$HOME/projects/agent-orchestration/logs/channel-watchdog.log"
TOKEN=$(cat ~/.claude/channels/telegram/.env | grep TELEGRAM_BOT_TOKEN | cut -d= -f2)
CHAT_ID="8556919856"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 재시작 시작" >> "$LOG"

# 재시작 알림
curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
  -d "chat_id=$CHAT_ID" -d "text=🔄 세션 재시작 중..." > /dev/null

# claude 프로세스 강제 종료
PIDS=$(pgrep -f "claude --dangerously-skip-permissions --channels")
[ -n "$PIDS" ] && kill -9 $PIDS 2>/dev/null && sleep 3

# 셸 프롬프트 확인 (claude가 완전히 종료될 때까지 대기)
for i in $(seq 1 10); do
  CONTENT=$(tmux capture-pane -t "$SESSION" -p -S -3 2>/dev/null)
  if echo "$CONTENT" | grep -q "^\$\|^❯\|^%"; then
    break
  fi
  sleep 1
done

# 새 Claude 시작
tmux send-keys -t "$SESSION" "env -u TELEGRAM_BOT_TOKEN claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official" Enter

sleep 6

# 완료 알림
curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
  -d "chat_id=$CHAT_ID" -d "text=✅ 새 세션 시작됨" > /dev/null

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 재시작 완료" >> "$LOG"
