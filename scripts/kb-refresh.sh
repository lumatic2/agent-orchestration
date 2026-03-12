#!/usr/bin/env bash
# kb-refresh.sh — knowledge-base Notion 인덱스 갱신
# 사용: bash ~/Desktop/agent-orchestration/scripts/kb-refresh.sh

set -euo pipefail

KB_DIR="$HOME/Desktop/knowledge-base"
INDEX_FILE="$KB_DIR/notion-company-index.md"
TODAY=$(date +%Y-%m-%d)

echo "=== Knowledge Base 갱신 ==="
echo "날짜: $TODAY"

# 회사 Notion 전체 검색
echo "회사 Notion 페이지 수집 중..."
RAW=$(NOTION_TOKEN=$COMPANY_NOTION_TOKEN PYTHONIOENCODING=utf-8 python3 ~/notion_db.py search "" --limit 200 2>&1)
COUNT=$(echo "$RAW" | wc -l | tr -d ' ')

echo "발견된 항목: $COUNT개"

# 헤더만 업데이트 (날짜 + 총 수)
sed -i '' "s/> 마지막 갱신: .*/> 마지막 갱신: $TODAY/" "$INDEX_FILE"
sed -i '' "s/> 총 페이지: .*/> 총 페이지: ${COUNT}개/" "$INDEX_FILE"

echo "인덱스 갱신 완료: $INDEX_FILE"
echo ""
echo "새 페이지 확인이 필요하면 전체 목록:"
echo "$RAW" | grep -v "^\[page\].*database_id" | head -30
