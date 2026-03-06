#!/bin/bash
# memory_update.sh — SHARED_MEMORY.md 구조적 업데이트
# 사용법: bash memory_update.sh <섹션> "내용"
#
# 지원 섹션:
#   recent_decisions  → ## Recent Decisions
#   active_projects   → ## Active Projects
#   conventions       → ## Conventions
#   known_issues      → ## Known Issues

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY="$(dirname "$SCRIPT_DIR")/SHARED_MEMORY.md"

SECTION="${1:-}"
ENTRY="${2:-}"

if [ -z "$SECTION" ] || [ -z "$ENTRY" ]; then
  echo "사용법: bash memory_update.sh <섹션> \"내용\""
  echo ""
  echo "섹션:"
  echo "  recent_decisions  → ## Recent Decisions"
  echo "  active_projects   → ## Active Projects"
  echo "  conventions       → ## Conventions"
  echo "  known_issues      → ## Known Issues"
  exit 1
fi

# 섹션 → 마크다운 헤더 매핑
case "$SECTION" in
  recent_decisions) HEADER="## Recent Decisions" ;;
  active_projects)  HEADER="## Active Projects" ;;
  conventions)      HEADER="## Conventions" ;;
  known_issues)     HEADER="## Known Issues" ;;
  *)
    echo "❌ 알 수 없는 섹션: $SECTION"
    echo "   지원: recent_decisions | active_projects | conventions | known_issues"
    exit 1
    ;;
esac

[ -f "$MEMORY" ] || { echo "❌ SHARED_MEMORY.md 없음: $MEMORY"; exit 1; }

DATE_PREFIX="$(date '+%Y-%m-%d')"
FULL_ENTRY="- **$DATE_PREFIX**: $ENTRY"

# 헤더 바로 다음 줄에 항목 삽입 (macOS/Linux 호환, sed -i 미사용)
awk -v header="$HEADER" -v entry="$FULL_ENTRY" '
  $0 == header { print; print ""; print entry; skip_blank=1; next }
  skip_blank && /^$/ { skip_blank=0; next }
  { skip_blank=0; print }
' "$MEMORY" > /tmp/sm_tmp.md && mv /tmp/sm_tmp.md "$MEMORY"

echo "✅ SHARED_MEMORY 업데이트: $HEADER"
echo "   $FULL_ENTRY"
