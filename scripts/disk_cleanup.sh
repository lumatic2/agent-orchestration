#!/usr/bin/env bash
# disk_cleanup.sh — 정기 디스크 정리
# cron: 매일 새벽 3시 실행

REPO="$HOME/projects/agent-orchestration"
LOG="$REPO/logs/disk_cleanup.log"
mkdir -p "$REPO/logs"

echo "[$(date '+%Y-%m-%d %H:%M')] 디스크 정리 시작" >> "$LOG"

# 1. OpenClaw 로그 7일 이상 된 것 삭제
find ~/.openclaw/logs -name "*.log" -mtime +7 -delete 2>/dev/null
find /tmp/openclaw -name "*.log" -mtime +3 -delete 2>/dev/null
echo "  - OpenClaw 로그 정리 완료" >> "$LOG"

# 2. 오케스트레이션 큐 완료 항목 30일 이상 된 것 아카이브
if [ -f "$REPO/scripts/orchestrate.sh" ]; then
  bash "$REPO/scripts/orchestrate.sh" --clean >> "$LOG" 2>&1
  echo "  - 큐 아카이브 완료" >> "$LOG"
fi

# 3. /tmp 임시 파일 정리 (task_brief 등)
find /tmp -name "task_brief*.md" -mtime +1 -delete 2>/dev/null
find /tmp -name "gemini_*.md" -mtime +1 -delete 2>/dev/null
echo "  - /tmp 임시 파일 정리 완료" >> "$LOG"

# 4. pip/brew 캐시 정리 (월 1회, 1일에만 실행)
if [ "$(date +%d)" = "01" ]; then
  brew cleanup --prune=30 >> "$LOG" 2>&1
  echo "  - brew 캐시 정리 완료" >> "$LOG"
fi

# 5. 디스크 사용량 기록
DISK_USED=$(df -h / | awk 'NR==2{print $5}')
echo "  - 디스크 사용량: $DISK_USED" >> "$LOG"

# 90% 초과 시 Telegram 알림
DISK_PCT=$(df / | awk 'NR==2{gsub(/%/,"",$5); print $5}')
if [ "$DISK_PCT" -gt 90 ]; then
  openclaw system event --text "경고: 디스크 사용량 ${DISK_PCT}% 초과" --mode now 2>/dev/null
fi

echo "[$(date '+%Y-%m-%d %H:%M')] 정리 완료" >> "$LOG"
