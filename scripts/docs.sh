#!/usr/bin/env bash
# docs.sh — 문서 생성 진입점
# Usage: bash docs.sh "주제" [type=proposal] [--dry-run] [--word]

set -euo pipefail

dry_run=false
word=false
args=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    --word)    word=true ;;
    *) args+=("$arg") ;;
  esac
done
set -- "${args[@]}"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: bash docs.sh \"주제\" [type=proposal] [--dry-run]" >&2
  exit 1
fi

TOPIC="$1"
DOC_TYPE="${2:-proposal}"

case "$DOC_TYPE" in
  proposal|report|business_plan|summary|meeting) ;;
  *)
    echo "[ERROR] type은 proposal|report|business_plan|summary|meeting 중 하나여야 합니다: $DOC_TYPE" >&2
    exit 1
    ;;
esac

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^[:alnum:]가-힣]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

type_guide() {
  case "$1" in
    proposal)
      cat <<'EOF'
권장 구조: cover → highlight_box(요약) → section(문제) → section(솔루션) → table_section(사양/가격) → two_col(장점 비교) → closing
EOF
      ;;
    report)
      cat <<'EOF'
권장 구조: cover → section(현황) → section(분석) → table_section(데이터) → bullet_section(시사점) → highlight_box(결론) → closing
EOF
      ;;
    business_plan)
      cat <<'EOF'
권장 구조: cover → highlight_box(한 줄 요약) → section(사업 개요) → section(시장 분석) → bullet_section(핵심 역량) → table_section(재무 계획) → closing
EOF
      ;;
    summary)
      cat <<'EOF'
권장 구조: cover → highlight_box(핵심 요약) → bullet_section(주요 내용) → section(결론) → closing
EOF
      ;;
    meeting)
      cat <<'EOF'
권장 구조: cover → table_section(참석자/안건) → bullet_section(논의 내용) → table_section(결정 사항 및 담당자) → section(다음 액션) → closing
EOF
      ;;
  esac
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ORCH="$SCRIPT_DIR/orchestrate.sh"
INJECT="$SCRIPT_DIR/inject-docs.py"
RENDER="$SCRIPT_DIR/render-docs.sh"

SLUG="$(slugify "$TOPIC")"
[ -n "$SLUG" ] || SLUG="docs"

DOCS_JSON="${SYS_TMP}/${SLUG}-${DOC_TYPE}.json"
OUT_HTML="${SYS_TMP}/${SLUG}-${DOC_TYPE}.html"

TYPE_GUIDE="$(type_guide "$DOC_TYPE")"

PROMPT=$(cat <<EOF
주제: ${TOPIC}
문서 타입: ${DOC_TYPE}

${TYPE_GUIDE}

다음 JSON 스키마로 문서 데이터를 생성해라. HTML 없이 JSON만 출력.

스키마:
{
  "meta": { "title": "문서 제목", "type": "${DOC_TYPE}" },
  "sections": [
    { "type": "cover", "data": { "title": "...", "subtitle": "...", "type_label": "...", "company": "...", "date": "YYYY-MM-DD" } },
    { "type": "section", "data": { "heading": "...", "body": "..." } },
    { "type": "bullet_section", "data": { "heading": "...", "items": [{"title": "...", "desc": "..."}] } },
    { "type": "table_section", "data": { "heading": "...", "headers": ["항목", "내용"], "rows": [["...", "..."]] } },
    { "type": "highlight_box", "data": { "label": "...", "text": "...", "sub_text": "..." } },
    { "type": "two_col", "data": { "heading": "...", "left_heading": "...", "left_items": ["..."], "right_heading": "...", "right_items": ["..."] } },
    { "type": "closing", "data": { "text": "...", "contact_name": "...", "contact_email": "...", "contact_phone": "" } }
  ]
}

규칙:
- 첫 섹션은 반드시 cover
- 마지막 섹션은 반드시 closing
- 모든 텍스트는 한국어
- section body는 3-5문장 분량
- JSON 외 다른 텍스트 출력 금지
EOF
)

if [ "$dry_run" = true ]; then
  echo "[DRY-RUN] bash \"$ORCH\" gemini \"<PROMPT>\" \"docs-json-${SLUG}-${DOC_TYPE}\""
  echo "[DRY-RUN] JSON 추출 -> $DOCS_JSON"
  echo "[DRY-RUN] python3 \"$INJECT\" \"$DOCS_JSON\" --out \"$OUT_HTML\""
  echo "[DRY-RUN] bash \"$RENDER\" \"$OUT_HTML\" \"${SLUG}-${DOC_TYPE}\""
  exit 0
fi

RAW_OUTPUT_FILE="$(safe_mktemp docs-gemini)"
TASK_NAME="docs-json-${SLUG}-${DOC_TYPE}"

echo "[1/4] Gemini JSON 생성 중..." >&2
bash "$ORCH" gemini "$PROMPT" "$TASK_NAME" >"$RAW_OUTPUT_FILE" 2>&1

echo "[2/4] JSON 블록 추출 중..." >&2
python3 - "$RAW_OUTPUT_FILE" "$DOCS_JSON" <<'PY'
import json
import sys
from pathlib import Path

raw_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
text = raw_path.read_text(encoding="utf-8", errors="replace")

decoder = json.JSONDecoder()
best_obj = None
best_len = -1
for i, ch in enumerate(text):
    if ch != "{":
        continue
    try:
        obj, end = decoder.raw_decode(text[i:])
    except json.JSONDecodeError:
        continue
    if isinstance(obj, dict) and "sections" in obj and end > best_len:
        best_obj = obj
        best_len = end

if best_obj is None:
    print("Gemini 출력에서 sections JSON을 찾지 못했습니다.", file=sys.stderr)
    sys.exit(1)

out_path.write_text(json.dumps(best_obj, ensure_ascii=False, indent=2), encoding="utf-8")
print(str(out_path))
PY

echo "[3/4] HTML 조립 중..." >&2
python3 "$INJECT" "$DOCS_JSON" --out "$OUT_HTML"

# Word 변환은 render-docs.sh가 HTML 삭제하기 전에 실행
if [ "$word" = true ]; then
  echo "[4/5] Word 변환 중..." >&2
  DOCX_PATH="${HOME}/Desktop/${SLUG}-${DOC_TYPE}.docx"
  pandoc "$OUT_HTML" --from html --to docx -o "$DOCX_PATH" 2>/dev/null \
    || echo "[WARN] pandoc 변환 실패" >&2
  [ -f "$DOCX_PATH" ] && echo "Word: $DOCX_PATH"
  echo "[5/5] PDF 렌더 중..." >&2
else
  echo "[4/4] PDF 렌더 중..." >&2
fi
bash "$RENDER" "$OUT_HTML" "${SLUG}-${DOC_TYPE}"

rm -f "$RAW_OUTPUT_FILE"
echo "완료: ${HOME}/Desktop/${SLUG}-${DOC_TYPE}.pdf"
