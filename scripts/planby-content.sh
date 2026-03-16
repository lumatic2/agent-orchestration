#!/usr/bin/env bash
set -euo pipefail

NOTION_DB_ID="31b85046ff558181b24cd5b94f371c75"
NOTION_DB_PY="$HOME/notion_db.py"
LOG_DIR="$HOME/projects/agent-orchestration/logs"
DATA_DIR="$HOME/projects/agent-orchestration/data"
HISTORY_FILE="$DATA_DIR/planby-title-history.txt"
TODAY=$(date +%Y-%m-%d)

mkdir -p "$LOG_DIR" "$DATA_DIR"
touch "$HISTORY_FILE"

LOG_FILE="$LOG_DIR/planby-content_${TODAY}.log"
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

if [ -z "${1:-}" ]; then
  DOW=$(date +%u)
  case "$DOW" in
    1) CONTENT_TYPE="주간뉴스" ;;
    3) CONTENT_TYPE="인사이트" ;;
    5) CONTENT_TYPE="Q&A" ;;
    *) CONTENT_TYPE="주간뉴스" ;;
  esac
  log "요일 자동 감지: ${DOW}요일 → $CONTENT_TYPE"
else
  CONTENT_TYPE="$1"
fi

RECENT_TITLES=$(tail -10 "$HISTORY_FILE" | sed 's/^/- /')
if [ -z "$RECENT_TITLES" ]; then
  RECENT_TITLES="- (최근 이력 없음)"
fi

RSS_HEADLINES=$(python3 - <<'PYEOF'
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET


def fetch_rss_headlines(query, max_items=5):
    url = f"https://news.google.com/rss/search?q={urllib.parse.quote(query)}&hl=ko&gl=KR&ceid=KR:ko"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            root = ET.fromstring(resp.read())
        items = root.findall('.//item')[:max_items]
        headlines = []
        for item in items:
            title_el = item.find('title')
            source_el = item.find('source')
            if title_el is not None and title_el.text:
                src = source_el.text if source_el is not None and source_el.text else ""
                headlines.append(f"- {title_el.text} ({src})")
        return "\n".join(headlines) if headlines else "(RSS 결과 없음)"
    except Exception as e:
        return f"(RSS 수집 실패: {e})"

print(fetch_rss_headlines("건설 부동산"))
PYEOF
)

log "=== Planby 콘텐츠 생성 시작 ($CONTENT_TYPE) ==="

BASE_CONTEXT="아래는 Google News에서 수집한 오늘의 최신 헤드라인이야 (참고용):
$RSS_HEADLINES

아래 제목들은 최근에 이미 작성된 글이니 유사한 주제는 피해줘:
$RECENT_TITLES

Planby는 건설/부동산 B2B 회사야.
독자는 건설사, 시행사, 부동산 개발사의 실무자 및 의사결정자.

출력 형식은 반드시 아래 구조를 지켜줘:

## TITLE
[제목]

## CATEGORY
[카테고리명]

## SOURCES
[참고한 뉴스 출처 URL 또는 매체명, 줄바꿈으로 구분]

## BODY
[본문]

## SLUG
[영문 소문자 URL 슬러그 - 하이픈 구분, 40자 이내. 예: construction-market-weekly-2026-03]

## META
[검색 노출용 메타 설명 - 한국어 100~120자. 검색 결과에 표시될 요약문]

## TAGS
[관련 태그 3~5개, 쉼표로 구분. 예: 건설시장,부동산,PF,수주,분양]"

case "$CONTENT_TYPE" in
  주간뉴스)
    PROMPT="오늘 날짜(${TODAY}) 기준으로 한국 건설/부동산 업계 최신 뉴스를 Google에서 검색해서,
가장 중요한 뉴스 3~5개를 선정하고 Planby 회사 블로그용 주간 뉴스 라운드업 아티클을 작성해줘.

본문은 1,000~1,500자로 작성하고,
구성은 도입(이슈 배경) → 뉴스 요약 3~5개(소제목 포함) → 시사점/인사이트 → 마무리 순서로 작성해.
카테고리는 반드시 주간뉴스로 작성해.

$BASE_CONTEXT"
    ;;
  인사이트)
    PROMPT="오늘 날짜(${TODAY}) 기준으로 한국 건설/부동산 업계에서 주목할만한 트렌드나 이슈 하나를
Google에서 검색하고 심층 분석한 인사이트 아티클을 작성해줘.

본문은 1,200~1,800자로 작성하고,
구성은 문제 제기 → 현황 데이터/사례 → 원인 분석 → 전망 → Planby 관점 시사점으로 작성해.
카테고리는 반드시 인사이트로 작성해.

$BASE_CONTEXT"
    ;;
  "Q&A")
    PROMPT="오늘 날짜(${TODAY}) 기준으로 건설/부동산 B2B 실무자들이 자주 궁금해하는
질문 하나를 선정해서 Q&A 형식의 아티클을 작성해줘.

본문은 800~1,200자로 작성하고,
구성은 Q(질문 배경 설명) → A(명확한 답변) → 실무 적용 팁 → 관련 참고사항으로 작성해.
카테고리는 반드시 Q&A로 작성해.

$BASE_CONTEXT"
    ;;
  *)
    log "알 수 없는 콘텐츠 유형: $CONTENT_TYPE (주간뉴스 | 인사이트 | Q&A)"
    exit 1
    ;;
esac

extract_section() {
  local section="$1"
  awk -v sec="$section" '
    $0 == "## " sec {found=1; next}
    found && /^## / {exit}
    found {print}
  ' <<< "$GEMINI_OUTPUT"
}

log "Gemini 호출 중..."
TEMP_OUTPUT=$(mktemp /tmp/planby-gemini-XXXXXX.txt)

gemini --yolo -m gemini-2.5-flash -p "$PROMPT" > "$TEMP_OUTPUT" 2>/dev/null || {
  log "❌ Gemini 호출 실패"
  cat "$TEMP_OUTPUT" >> "$LOG_FILE"
  rm -f "$TEMP_OUTPUT"
  exit 1
}

GEMINI_OUTPUT=$(cat "$TEMP_OUTPUT")
log "Gemini 응답 수신 ($(wc -c < "$TEMP_OUTPUT") bytes)"

TITLE=$(extract_section "TITLE" | awk 'NF{print; exit}')
if [ -z "$TITLE" ]; then
  TITLE=$(echo "$GEMINI_OUTPUT" | grep '^## ' | grep -v '^## CATEGORY\|^## SOURCES\|^## BODY\|^## TITLE\|^## SLUG\|^## META\|^## TAGS' | head -1 | sed 's/^## //')
fi

SOURCES=$(extract_section "SOURCES" | head -5 | tr '\n' ', ' | sed 's/, $//')
BODY=$(extract_section "BODY")
SLUG=$(extract_section "SLUG" | awk 'NF{print; exit}' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-40)
META=$(extract_section "META" | awk 'NF{print; exit}')
TAGS=$(extract_section "TAGS" | awk 'NF{print; exit}')
CATEGORY="$CONTENT_TYPE"

if [ -z "$TITLE" ]; then
  TITLE="${CONTENT_TYPE} - ${TODAY}"
  log "⚠️ TITLE 파싱 실패 → fallback: $TITLE"
fi
if [ -z "$BODY" ]; then
  BODY="콘텐츠 생성 결과를 파싱하지 못했습니다. 원문을 로그에서 확인하세요."
  log "⚠️ BODY 파싱 실패 → fallback 본문 사용"
fi

log "제목: $TITLE"
log "카테고리: $CATEGORY"

echo "${TODAY}|${CONTENT_TYPE}|${TITLE}" >> "$HISTORY_FILE"

TEMP_BODY=$(mktemp /tmp/planby-body-XXXXXX.txt)
printf '%s\n' "$BODY" > "$TEMP_BODY"

log "Notion DB에 페이지 생성 중..."
PAGE_ID=$(python3 "$NOTION_DB_PY" create --database-id "$NOTION_DB_ID" --title "$TITLE" --content-file "$TEMP_BODY") || {
  log "❌ Notion 페이지 생성 실패"
  rm -f "$TEMP_OUTPUT" "$TEMP_BODY"
  exit 1
}

log "페이지 생성됨: $PAGE_ID"

export PAGE_ID TODAY CATEGORY SOURCES SLUG META TAGS
python3 - <<'PYEOF'
import os
import sys
import json
import urllib.request
import urllib.error

token = os.getenv("PERSONAL_NOTION_TOKEN")
if not token:
    print("PERSONAL_NOTION_TOKEN not set", file=sys.stderr)
    sys.exit(1)

page_id = os.environ["PAGE_ID"]
headers = {
    "Authorization": f"Bearer {token}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json",
}

sources_text = os.getenv("SOURCES", "")[:2000]
slug = os.getenv("SLUG", "")[:200]
meta = os.getenv("META", "")[:200]
tags_raw = os.getenv("TAGS", "")
tag_items = [{"name": t.strip()} for t in tags_raw.split(",") if t.strip()][:5]

properties = {
    "카테고리": {"select": {"name": os.getenv("CATEGORY", "")}},
    "상태": {"select": {"name": "초안"}},
    "생성일": {"date": {"start": os.getenv("TODAY", "")}},
    "뉴스출처": {"rich_text": [{"type": "text", "text": {"content": sources_text}}]} if sources_text else {"rich_text": []},
    "슬러그": {"rich_text": [{"type": "text", "text": {"content": slug}}]} if slug else {"rich_text": []},
    "메타설명": {"rich_text": [{"type": "text", "text": {"content": meta}}]} if meta else {"rich_text": []},
    "태그": {"multi_select": tag_items},
}

req = urllib.request.Request(
    f"https://api.notion.com/v1/pages/{page_id}",
    data=json.dumps({"properties": properties}).encode("utf-8"),
    headers=headers,
    method="PATCH",
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
