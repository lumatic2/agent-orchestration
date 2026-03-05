#!/bin/bash
# session-logger.sh — Claude Code Stop hook
# 세션 종료 시 작업 요약을 ~/knowledge-log/에 저장

LOG_DIR="$HOME/knowledge-log"
mkdir -p "$LOG_DIR"

DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M)
LOG_FILE="$LOG_DIR/$DATE.md"

# 세션 정보
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
CWD="${PWD:-unknown}"

# 오늘 파일이 없으면 헤더 생성
if [ ! -f "$LOG_FILE" ]; then
    cat > "$LOG_FILE" << EOF
# 작업 로그 — $DATE

---
EOF
fi

# 세션 엔트리 추가
cat >> "$LOG_FILE" << EOF

## $TIME | $(basename "$CWD")

- **세션 ID**: \`$SESSION_ID\`
- **작업 디렉토리**: \`$CWD\`
- **종료 시각**: $TIME

### 메모
_이 세션에서 한 작업:_

<!-- Claude가 자동 기록한 항목 -->
EOF

echo "[session-logger] 로그 저장: $LOG_FILE"
