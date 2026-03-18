#!/usr/bin/env bash
# notion-upload.sh — 슬라이드 PDF를 Notion 페이지로 업로드
#
# 사용법:
#   bash notion-upload.sh <pdf_file> [--title "제목"] [--parent-page-id <id>] [--dry-run]
#
# 예시:
#   bash notion-upload.sh ~/Desktop/한국커피역사.pdf --title "한국 커피의 역사"
#   bash notion-upload.sh ~/Desktop/slides.pdf --parent-page-id abc123 --dry-run
#
# 환경변수:
#   PERSONAL_NOTION_TOKEN   — Notion 통합 토큰 (필수)
#   NOTION_SLIDES_PAGE_ID   — 업로드 대상 부모 페이지 ID (선택, 미설정 시 --parent-page-id 필수)

set -uo pipefail

DRY_RUN=false
PDF_FILE=""
TITLE=""
PARENT_PAGE_ID="${NOTION_SLIDES_PAGE_ID:-}"

NOTION_DB="$(cd "$(dirname "$0")" && pwd)/notion_db.py"

usage() {
  echo "Usage: bash notion-upload.sh <pdf_file> [--title <제목>] [--parent-page-id <id>] [--dry-run]" >&2
  exit 1
}

# ── 인자 파싱 ────────────────────────────────────────────────────────────────
args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --title)
      shift
      [ "$#" -eq 0 ] && { echo "[ERROR] --title 뒤에 값 필요" >&2; exit 1; }
      TITLE="$1"
      shift
      ;;
    --title=*)
      TITLE="${1#--title=}"
      shift
      ;;
    --parent-page-id)
      shift
      [ "$#" -eq 0 ] && { echo "[ERROR] --parent-page-id 뒤에 값 필요" >&2; exit 1; }
      PARENT_PAGE_ID="$1"
      shift
      ;;
    --parent-page-id=*)
      PARENT_PAGE_ID="${1#--parent-page-id=}"
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "[ERROR] 알 수 없는 옵션: $1" >&2
      usage
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

# ── 필수 인자 확인 ───────────────────────────────────────────────────────────
if [ "${#args[@]}" -lt 1 ]; then
  echo "[ERROR] PDF 파일 경로가 필요합니다." >&2
  usage
fi

PDF_FILE="${args[0]}"

# 제목 미입력 시 파일명에서 추출
if [ -z "$TITLE" ]; then
  TITLE="$(basename "$PDF_FILE" .pdf)"
fi

# ── dry-run 모드 ─────────────────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
  echo "[DRY-RUN] 업로드 시뮬레이션:"
  echo "  PDF:    $PDF_FILE"
  echo "  제목:   $TITLE"
  echo "  부모:   ${PARENT_PAGE_ID:-미설정 (NOTION_SLIDES_PAGE_ID 환경변수 필요)}"
  echo "  단계:   1) 하위 페이지 생성 → 2) PDF 파일 업로드 → 3) 완료"
  exit 0
fi

# ── 사전 조건 검사 ───────────────────────────────────────────────────────────
if [ -z "${PERSONAL_NOTION_TOKEN:-}" ]; then
  echo "[ERROR] PERSONAL_NOTION_TOKEN 미설정" >&2
  echo "  ~/.zshenv에 추가: export PERSONAL_NOTION_TOKEN=secret_xxx" >&2
  exit 1
fi

if [ -z "$PARENT_PAGE_ID" ]; then
  echo "[ERROR] 업로드 대상 Notion 페이지 ID가 없습니다." >&2
  echo "  방법 1: --parent-page-id <id> 옵션 사용" >&2
  echo "  방법 2: export NOTION_SLIDES_PAGE_ID=<id> 환경변수 설정" >&2
  exit 1
fi

if [ ! -f "$PDF_FILE" ]; then
  echo "[ERROR] 파일 없음: $PDF_FILE" >&2
  exit 1
fi

if [ ! -f "$NOTION_DB" ]; then
  echo "[ERROR] notion_db.py 없음: $NOTION_DB" >&2
  exit 1
fi

# ── Step 1: 하위 페이지 생성 ────────────────────────────────────────────────
echo "[1/2] Notion 페이지 생성 중: $TITLE"

PAGE_JSON=$(PERSONAL_NOTION_TOKEN="$PERSONAL_NOTION_TOKEN" \
  python3 "$NOTION_DB" create \
    --parent-page-id "$PARENT_PAGE_ID" \
    --title "$TITLE" \
    --json 2>&1)

PAGE_ID=$(echo "$PAGE_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('id',''))
except Exception as e:
    print('', end='')
" 2>/dev/null)

if [ -z "$PAGE_ID" ]; then
  echo "[ERROR] 페이지 생성 실패:" >&2
  echo "$PAGE_JSON" >&2
  exit 1
fi

echo "  → 페이지 ID: $PAGE_ID"

# ── Step 2: PDF 파일 업로드 ──────────────────────────────────────────────────
echo "[2/2] PDF 업로드 중: $(basename "$PDF_FILE")"

UPLOAD_RESULT=$(PERSONAL_NOTION_TOKEN="$PERSONAL_NOTION_TOKEN" \
  python3 "$NOTION_DB" upload-file "$PAGE_ID" \
    --file "$PDF_FILE" 2>&1)

if echo "$UPLOAD_RESULT" | grep -q "uploaded"; then
  echo "[DONE] 업로드 완료"
  echo "  제목:   $TITLE"
  echo "  페이지: https://notion.so/${PAGE_ID//-/}"
  exit 0
else
  echo "[ERROR] 업로드 실패:" >&2
  echo "$UPLOAD_RESULT" >&2
  exit 1
fi
