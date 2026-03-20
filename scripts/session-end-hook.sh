#!/usr/bin/env bash
# Stop hook — Claude 응답 완료 시마다 실행 (lightweight)
# 역할: 큐 대기 태스크 확인 + 중단 로그 기록

LOG_FILE="$HOME/projects/agent-orchestration/logs/stop_hook.log"
QUEUE_DIR="$HOME/projects/agent-orchestration/queue"

timestamp=$(date '+%Y-%m-%d %H:%M:%S')

# --- 큐 대기 태스크 확인 ---
pending=()
if [ -d "$QUEUE_DIR" ]; then
  while IFS= read -r f; do
    status=$(grep -m1 '"status"' "$f" 2>/dev/null | sed 's/.*: *"\(.*\)".*/\1/')
    name=$(grep -m1 '"name"' "$f" 2>/dev/null | sed 's/.*: *"\(.*\)".*/\1/')
    if [[ "$status" == "pending" || "$status" == "dispatched" || "$status" == "stale" ]]; then
      pending+=("$name($status)")
    fi
  done < <(find "$QUEUE_DIR" -name "task.json" 2>/dev/null)
fi

# --- 로그 기록 ---
echo "[$timestamp] STOP" >> "$LOG_FILE"

# --- 대기 태스크 있으면 출력 ---
if [ ${#pending[@]} -gt 0 ]; then
  echo ""
  echo "⏳ 큐 대기 중: ${pending[*]}"
fi
