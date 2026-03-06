#!/usr/bin/env bash
# ============================================================
# planby-content.sh — Planby 자동 콘텐츠 생성 스크립트
#
# Gemini로 건설/부동산 뉴스 검색 + 인사이트 아티클 생성 → 개인 Notion DB 저장
#
# Usage:
#   bash planby-content.sh [type]
#   type: 주간뉴스 (기본값) | 인사이트 | Q&A
#
# Cron 예시 (주 3회: 월수금 오전 8시):
#   0 8 * * 1,3,5 bash /Users/luma3/Desktop/agent-orchestration/scripts/planby-content.sh
# ============================================================
set -euo pipefail

NOTION_DB_ID="31b85046ff558181b24cd5b94f371c75"
NOTION_DB_PY="$HOME/notion_db.py"
LOG_DIR="$HOME/Desktop/agent-orchestration/logs"
TODAY=$(date +%Y-%m-%d)
CONTENT_TYPE="${1:-주간뉴스}"

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/planby-content_${TODAY}.log"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "=== Planby 콘텐츠 생성 시작 ($CONTENT_TYPE) ==="

# ============================================================
# 콘텐츠 유형별 프롬프트
# ============================================================
case "$CONTENT_TYPE" in
  주간뉴스)
    PROMPT="오늘 날짜(${TODAY}) 기준으로 한국 건설/부동산 업계 최신 뉴스를 Google에서 검색해서,
가장 중요한 뉴스 3~5개를 선정하고 Planby 회사 블로그용 주간 뉴스 라운드업 아티클을 작성해줘.

Planby는 건설/부동산 B2B 회사야.
독자는 건설사, 시행사, 부동산 개발사의 실무자 및 의사결정자.

출력 형식은 반드시 아래 구조를 지켜줘 (파싱에 사용됨):

## TITLE
[제목 - 50자 이내, 이번 주 핵심 이슈 중심]

## CATEGORY
주간뉴스

## SOURCES
[참고한 뉴스 출처 URL 또는 매체명, 줄바꿈으로 구분]

## BODY
[본문 - 1,000~1,500자. 마크다운 사용 가능.
구성: 도입(이슈 배경) → 뉴스 요약 3~5개(소제목 포함) → 시사점/인사이트 → 마무리]"
    ;;

  인사이트)
    PROMPT="오늘 날짜(${TODAY}) 기준으로 한국 건설/부동산 업계에서 주목할만한 트렌드나 이슈 하나를
Google에서 검색하고 심층 분석한 인사이트 아티클을 작성해줘.

Planby는 건설/부동산 B2B 회사야.
독자는 건설사, 시행사, 부동산 개발사의 실무자 및 의사결정자.

출력 형식은 반드시 아래 구조를 지켜줘:

## TITLE
[제목 - 50자 이내, 분석적 관점이 드러나게]

## CATEGORY
인사이트

## SOURCES
[참고한 뉴스 출처 URL 또는 매체명, 줄바꿈으로 구분]

## BODY
[본문 - 1,200~1,800자. 마크다운 사용 가능.
구성: 문제 제기 → 현황 데이터/사례 → 원인 분석 → 전망 → Planby 관점 시사점]"
    ;;

  "Q&A")
    PROMPT="오늘 날짜(${TODAY}) 기준으로 건설/부동산 B2B 실무자들이 자주 궁금해하는
질문 하나를 선정해서 Q&A 형식의 아티클을 작성해줘.

Planby는 건설/부동산 B2B 회사야.
독자는 건설사, 시행사, 부동산 개발사의 실무자 및 의사결정자.

출력 형식은 반드시 아래 구조를 지켜줘:

## TITLE
[제목 - 'Q. [질문]' 형식, 50자 이내]

## CATEGORY
Q&A

## SOURCES
[참고한 자료 출처]

## BODY
[본문 - 800~1,200자.
구성: Q(질문 배경 설명) → A(명확한 답변) → 실무 적용 팁 → 관련 참고사항]"
    ;;

  *)
    log "알 수 없는 콘텐츠 유형: $CONTENT_TYPE (주간뉴스 | 인사이트 | Q&A)"
    exit 1
    ;;
esac

# ============================================================
# 1단계: Gemini 웹검색 + 아티클 생성
# ============================================================
log "Gemini 호출 중..."
TEMP_OUTPUT=$(mktemp /tmp/planby-gemini-XXXXXX.txt)

gemini \
  --yolo \
  -m gemini-2.5-flash \
  -p "$PROMPT" > "$TEMP_OUTPUT" 2>/dev/null || {
  log "❌ Gemini 호출 실패"
  cat "$TEMP_OUTPUT" >> "$LOG_FILE"
  rm -f "$TEMP_OUTPUT"
  exit 1
}

GEMINI_OUTPUT=$(cat "$TEMP_OUTPUT")
log "Gemini 응답 수신 ($(wc -c < "$TEMP_OUTPUT") bytes)"

# ============================================================
# 2단계: 출력 파싱
# Gemini는 ## TITLE 헤더 없이 제목을 "## 제목텍스트" 형식으로 직접 출력함
# 구조: 첫 번째 ## 줄 = 제목, ## CATEGORY / ## SOURCES / ## BODY 섹션
# ============================================================

# 제목: 첫 번째 "## " 줄에서 추출
TITLE=$(echo "$GEMINI_OUTPUT" | grep "^## " | grep -v "^## CATEGORY\|^## SOURCES\|^## BODY\|^## TITLE" | head -1 | sed 's/^## //')

# SOURCES: ## SOURCES ~ ## BODY 사이
SOURCES=$(echo "$GEMINI_OUTPUT" | awk '/^## SOURCES/{found=1; next} found && /^## /{exit} found && NF{print}' | head -5 | tr '\n' ', ' | sed 's/,$//')

# BODY: 첫 번째 ## BODY 이후 전체 (다음 아티클 포함)
BODY=$(echo "$GEMINI_OUTPUT" | awk '/^## BODY/{found=1; next} found{print}' | head -100)

# CATEGORY는 스크립트 인자로 결정 (Gemini 출력 무시)
CATEGORY="$CONTENT_TYPE"

# 파싱 실패 시 fallback
if [ -z "$TITLE" ]; then
  TITLE="${CONTENT_TYPE} - ${TODAY}"
  log "⚠️  TITLE 파싱 실패 → fallback: $TITLE"
fi

log "제목: $TITLE"
log "카테고리: $CATEGORY"

# ============================================================
# 3단계: Notion DB에 페이지 생성
# ============================================================
TEMP_BODY=$(mktemp /tmp/planby-body-XXXXXX.txt)
echo "$BODY" > "$TEMP_BODY"

log "Notion DB에 페이지 생성 중..."
PAGE_ID=$(python3 "$NOTION_DB_PY" create \
  --database-id "$NOTION_DB_ID" \
  --title "$TITLE" \
  --content-file "$TEMP_BODY") || {
  log "❌ Notion 페이지 생성 실패"
  rm -f "$TEMP_OUTPUT" "$TEMP_BODY"
  exit 1
}

log "페이지 생성됨: $PAGE_ID"

# ============================================================
# 4단계: 속성 업데이트 (카테고리, 상태, 생성일, 뉴스출처)
# ============================================================
python3 - << PYEOF
import os, sys
import urllib.request, json

token = os.getenv("PERSONAL_NOTION_TOKEN")
if not token:
    print("PERSONAL_NOTION_TOKEN not set", file=sys.stderr)
    sys.exit(1)

page_id = "$PAGE_ID"
headers = {
    "Authorization": f"Bearer {token}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json"
}

sources_text = """$SOURCES"""[:2000]  # Notion rich_text 2000자 제한

data = {
    "properties": {
        "카테고리": {"select": {"name": "$CATEGORY"}},
        "상태": {"select": {"name": "초안"}},
        "생성일": {"date": {"start": "$TODAY"}},
        "뉴스출처": {"rich_text": [{"type": "text", "text": {"content": sources_text}}]}
    }
}

req = urllib.request.Request(
    f"https://api.notion.com/v1/pages/{page_id}",
    data=json.dumps(data).encode("utf-8"),
    headers=headers,
    method="PATCH"
)

try:
    with urllib.request.urlopen(req) as resp:
        print(f"속성 업데이트 완료 (HTTP {resp.status})")
except urllib.error.HTTPError as e:
    print(f"속성 업데이트 실패: {e.code} {e.read().decode()}", file=sys.stderr)
    sys.exit(1)
PYEOF

rm -f "$TEMP_OUTPUT" "$TEMP_BODY"
log "✅ 완료: '$TITLE' → Notion DB 저장 (상태: 초안)"
log "   Notion 링크: https://www.notion.so/${PAGE_ID//-/}"
