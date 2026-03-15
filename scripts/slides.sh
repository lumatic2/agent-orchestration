#!/usr/bin/env bash
# slides.sh — Option B 슬라이드 생성 진입점
# Usage: bash slides.sh "주제" [슬라이드수=9] [--dry-run]

set -euo pipefail

dry_run=false
args=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    *) args+=("$arg") ;;
  esac
done
set -- "${args[@]}"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: bash slides.sh \"주제\" [슬라이드수=9] [--dry-run]" >&2
  exit 1
fi

TOPIC="$1"
SLIDE_N="${2:-9}"
if ! [[ "$SLIDE_N" =~ ^[0-9]+$ ]]; then
  echo "[ERROR] 슬라이드 수는 숫자여야 합니다: $SLIDE_N" >&2
  exit 1
fi

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^[:alnum:]가-힣]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ORCH="$SCRIPT_DIR/orchestrate.sh"
INJECT="$SCRIPT_DIR/inject-slides.py"
RENDER="$SCRIPT_DIR/render-slides.sh"

SLUG="$(slugify "$TOPIC")"
[ -n "$SLUG" ] || SLUG="slides"
# Windows에서 /tmp는 Node.js가 접근 못함 → AppData/Local/Temp 사용
WIN_TEMP="${HOME}/AppData/Local/Temp"
SLIDES_JSON="${WIN_TEMP}/${SLUG}.json"
OUT_HTML="${WIN_TEMP}/${SLUG}.html"

PROMPT=$(cat <<EOF
주제: ${TOPIC}
슬라이드 수: ${SLIDE_N}

다음 JSON 스키마로 슬라이드 데이터를 생성해라. HTML 없이 JSON만 출력.

스키마:
{
  "meta": { "title": "슬라이드 제목" },
  "slides": [
    { "type": "title_panel", "data": { "title": "...", "subtitle": "...", "points": ["..."] } },
    { "type": "card_grid", "data": { "badge": "섹션명", "title": "...", "cards": [{"icon": "target", "title": "...", "desc": "..."}] } },
    { "type": "numbered_list", "data": { "badge": "...", "title": "...", "subtitle": "...", "items": [{"num": "01", "title": "...", "desc": "..."}] } },
    { "type": "bar_chart", "data": { "badge": "...", "title": "...", "bars": [{"label": "...", "value": 85, "max": 100}], "hero_number": "85%", "hero_label": "...", "sub_stats": [{"label": "...", "value": "..."}] } },
    { "type": "big_statement", "data": { "badge": "...", "line1": "...", "line2": "...", "line3": "..." } },
    { "type": "comparison_table", "data": { "badge": "...", "title": "...", "left_label": "...", "right_label": "...", "rows": [{"aspect": "...", "left": "...", "right": "...", "highlight": null}] } },
    { "type": "timeline", "data": { "badge": "...", "title": "...", "steps": [{"year": "2020", "title": "...", "desc": "..."}] } },
    { "type": "quote_close", "data": { "quote": "...", "author": "...", "cta": "..."} }
  ]
}

규칙:
- 첫 슬라이드는 반드시 title_panel
- 마지막 슬라이드는 반드시 quote_close
- 중간 슬라이드는 주제에 맞게 타입 선택 (같은 타입 3회 이상 연속 금지)
- 모든 텍스트는 한국어
- card_grid의 icon 필드는 반드시 다음 중 하나: check, rocket, target, chart, gear, star, lightning, shield, users, globe, clock, arrow, layers, code, database, flag, leaf, diamond, box, lock, search, graph, award, eye
- JSON 외 다른 텍스트 출력 금지
EOF
)

if [ "$dry_run" = true ]; then
  echo "[DRY-RUN] bash \"$ORCH\" gemini \"<PROMPT>\" \"slides-json-${SLUG}\""
  echo "[DRY-RUN] JSON 추출 -> $SLIDES_JSON"
  echo "[DRY-RUN] python3 \"$INJECT\" \"$SLIDES_JSON\" --out \"$OUT_HTML\""
  echo "[DRY-RUN] bash \"$RENDER\" \"$OUT_HTML\" \"$SLUG\""
  exit 0
fi

RAW_OUTPUT_FILE="$(mktemp "/tmp/slides-gemini-${SLUG}-XXXXXX.txt")"
TASK_NAME="slides-json-${SLUG}"

echo "[1/4] Gemini JSON 생성 중..." >&2
bash "$ORCH" gemini "$PROMPT" "$TASK_NAME" >"$RAW_OUTPUT_FILE" 2>&1

echo "[2/4] JSON 블록 추출 중..." >&2
python3 - "$RAW_OUTPUT_FILE" "$SLIDES_JSON" <<'PY'
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
    if isinstance(obj, dict) and "slides" in obj and end > best_len:
        best_obj = obj
        best_len = end

if best_obj is None:
    print("Gemini 출력에서 slides JSON을 찾지 못했습니다.", file=sys.stderr)
    sys.exit(1)

out_path.write_text(json.dumps(best_obj, ensure_ascii=False, indent=2), encoding="utf-8")
print(str(out_path))
PY

echo "[3/4] HTML 조립 중..." >&2
python3 "$INJECT" "$SLIDES_JSON" --out "$OUT_HTML"

echo "[4/4] PDF 렌더 중..." >&2
bash "$RENDER" "$OUT_HTML" "$SLUG"

rm -f "$RAW_OUTPUT_FILE"
echo "완료: ${HOME}/Desktop/${SLUG}.pdf"
