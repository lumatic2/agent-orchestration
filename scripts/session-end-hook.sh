#!/usr/bin/env bash
# Stop hook — Claude 응답 완료 시마다 실행 (lightweight, VS Code 호환)
# 역할: 타임스탬프 로그 + 큐 상태 파일 갱신

LOG_FILE="$HOME/projects/agent-orchestration/logs/stop_hook.log"
STATUS_FILE="$HOME/projects/agent-orchestration/logs/queue_status.txt"
QUEUE_DIR="$HOME/projects/agent-orchestration/queue"

timestamp=$(date '+%Y-%m-%d %H:%M:%S')

# --- 큐 대기 태스크 확인 ---
pending=()
if [ -d "$QUEUE_DIR" ]; then
  while IFS= read -r f; do
    status=$(grep -m1 '"status"' "$f" 2>/dev/null | sed 's/.*: *"\(.*\)".*/\1/')
    name=$(grep -m1 '"name"' "$f" 2>/dev/null | sed 's/.*: *"\(.*\)".*/\1/')
    if [[ "$status" == "pending" || "$status" == "dispatched" || "$status" == "stale" ]]; then
      pending+=("[$status] $name")
    fi
  done < <(find "$QUEUE_DIR" -name "task.json" 2>/dev/null)
fi

# --- 타임스탬프 로그 ---
echo "[$timestamp] STOP | pending: ${#pending[@]}" >> "$LOG_FILE"

# --- 큐 상태 파일 갱신 (VS Code에서 확인 가능) ---
{
  echo "Last stop: $timestamp"
  echo "Pending tasks: ${#pending[@]}"
  if [ ${#pending[@]} -gt 0 ]; then
    for t in "${pending[@]}"; do
      echo "  - $t"
    done
  fi
} > "$STATUS_FILE"

# --- 대기 태스크 있으면 Telegram 알림 ---
if [ ${#pending[@]} -gt 0 ]; then
  bash ~/.claude/telegram-notify.sh "Claude stopped. Pending: ${pending[*]}" 2>/dev/null || true
fi
