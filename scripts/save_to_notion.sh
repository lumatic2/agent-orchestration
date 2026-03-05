#!/bin/bash
# save_to_notion.sh — 에이전트 결과 Notion 저장 유틸리티
# 사용법: bash save_to_notion.sh --agent <tax|expert|content> --title "제목" --content "본문"
#
# 특징:
#   - 비동기 실행 (&) — 에이전트 차단 없음
#   - per-agent 자식 페이지 첫 실행 시 자동 생성 후 ID 캐시
#   - PERSONAL_NOTION_TOKEN 없으면 조용히 종료

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="$HOME/.config/agent-orchestration"
CONF_FILE="$CONF_DIR/notion_pages.conf"
NOTION_DB="$SCRIPT_DIR/notion_db.py"

# ── arg 파싱 ─────────────────────────────────────────────
AGENT=""
TITLE=""
CONTENT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)   AGENT="$2";   shift 2 ;;
    --title)   TITLE="$2";   shift 2 ;;
    --content) CONTENT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# ── 사전 조건 검사 ───────────────────────────────────────
[ -z "$PERSONAL_NOTION_TOKEN" ] && exit 0   # 선택적 기능 — 조용히 종료
[ -z "$AGENT" ]   && { echo "[NOTION] --agent 필요 (tax|expert|content)"; exit 1; }
[ -z "$TITLE" ]   && TITLE="$(date '+%Y-%m-%d %H:%M') 결과"
[ -z "$CONTENT" ] && { echo "[NOTION] --content 없음 — 저장 건너뜀"; exit 0; }

mkdir -p "$CONF_DIR"
touch "$CONF_FILE"

# ── conf 헬퍼 ────────────────────────────────────────────
conf_get() { grep "^$1=" "$CONF_FILE" | cut -d= -f2- | head -1; }
conf_set() {
  local key="$1" val="$2"
  if grep -q "^$key=" "$CONF_FILE" 2>/dev/null; then
    awk -v k="$key" -v v="$val" 'BEGIN{FS=OFS="="} $1==k{$2=v} 1' \
      "$CONF_FILE" > /tmp/_notion_conf_tmp && mv /tmp/_notion_conf_tmp "$CONF_FILE"
  else
    echo "$key=$val" >> "$CONF_FILE"
  fi
}

# ── 부모 페이지 확인/생성 ────────────────────────────────
PARENT_KEY="NOTION_PARENT_AI_RESULTS"
PARENT_ID=$(conf_get "$PARENT_KEY")

if [ -z "$PARENT_ID" ]; then
  # 이미 setup 단계에서 생성됐어야 함 — 없으면 에러
  echo "[NOTION] 부모 페이지 ID 없음. 먼저 one-time setup을 실행하세요."
  echo "         bash save_to_notion.sh --setup"
  exit 1
fi

# ── per-agent 자식 페이지 확인/생성 ─────────────────────
case "$AGENT" in
  tax)     AGENT_KEY="NOTION_PAGE_TAX";     AGENT_LABEL="🧾 세무 에이전트 결과" ;;
  expert)  AGENT_KEY="NOTION_PAGE_EXPERT";  AGENT_LABEL="👨‍⚕️ 전문직 에이전트 결과" ;;
  content) AGENT_KEY="NOTION_PAGE_CONTENT"; AGENT_LABEL="✍️ 콘텐츠 파이프라인 결과" ;;
  *)
    echo "[NOTION] 알 수 없는 에이전트: $AGENT (tax|expert|content)"
    exit 1
    ;;
esac

AGENT_PAGE_ID=$(conf_get "$AGENT_KEY")

if [ -z "$AGENT_PAGE_ID" ]; then
  echo "[NOTION] $AGENT_LABEL 페이지 생성 중..."
  RESULT=$(PYTHONIOENCODING=utf-8 python3 "$NOTION_DB" create \
    --parent-page-id "$PARENT_ID" \
    --title "$AGENT_LABEL" \
    --json 2>/dev/null)
  AGENT_PAGE_ID=$(echo "$RESULT" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null)
  if [ -z "$AGENT_PAGE_ID" ]; then
    echo "[NOTION] 페이지 생성 실패 — 저장 건너뜀"
    exit 0
  fi
  # Notion ID 정규화 (하이픈 제거 후 재삽입)
  AGENT_PAGE_ID=$(echo "$AGENT_PAGE_ID" | tr -d '-')
  conf_set "$AGENT_KEY" "$AGENT_PAGE_ID"
  echo "[NOTION] 페이지 생성 완료: $AGENT_PAGE_ID"
fi

# ── 본문 append (백그라운드) ─────────────────────────────
BODY="## $TITLE
**시각**: $(date '+%Y-%m-%d %H:%M')

$CONTENT

---"

PYTHONIOENCODING=utf-8 python3 "$NOTION_DB" append "$AGENT_PAGE_ID" \
  --content "$BODY" &

echo "[NOTION] 저장 중... ($AGENT_LABEL)"
