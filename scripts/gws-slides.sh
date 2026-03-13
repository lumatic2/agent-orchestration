#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
  echo "Usage: bash gws-slides.sh \"주제\" [슬라이드수=9] [색상프리셋=auto]" >&2
  exit 1
fi

TOPIC="$1"
SLIDE_N="${2:-9}"
PRESET_INPUT="${3:-auto}"

if ! [[ "$SLIDE_N" =~ ^[0-9]+$ ]] || [ "$SLIDE_N" -lt 1 ]; then
  echo "[ERROR] 슬라이드 수는 1 이상의 숫자여야 합니다: $SLIDE_N" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$REPO_DIR/slides_config.yaml"
ORCH="$SCRIPT_DIR/orchestrate.sh"
LOG_DIR="$REPO_DIR/logs"

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^[:alnum:]가-힣]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

SLUG="$(slugify "$TOPIC")"
[ -n "$SLUG" ] || SLUG="gws-slides"
TMP_JSON="/tmp/gws_slide_data_${SLUG}.json"
cleanup() {
  rm -f "$TMP_JSON"
}
trap cleanup EXIT

if [ ! -f "$CONFIG_FILE" ]; then
  echo "[ERROR] 설정 파일 없음: $CONFIG_FILE" >&2
  exit 1
fi

GWS_CFG_OUT="$(python3 - "$CONFIG_FILE" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
template_id = ""
default_preset = "light_navy"

in_gws = False
for line in text.splitlines():
    if re.match(r"^gws:\s*$", line):
        in_gws = True
        continue
    if in_gws and re.match(r"^[^\s#][^:]*:\s*", line):
        break
    if in_gws:
        m_template = re.match(r'^\s{2}template_id:\s*(.*)\s*$', line)
        if m_template:
            val = m_template.group(1).split("#", 1)[0].strip().strip('"').strip("'")
            template_id = val
            continue
        m_preset = re.match(r'^\s{2}default_preset:\s*(.*)\s*$', line)
        if m_preset:
            val = m_preset.group(1).split("#", 1)[0].strip().strip('"').strip("'")
            if val:
                default_preset = val

print(template_id)
print(default_preset)
PY
)"

TEMPLATE_ID="$(echo "$GWS_CFG_OUT" | sed -n '1p')"
DEFAULT_PRESET="$(echo "$GWS_CFG_OUT" | sed -n '2p')"
[ -n "$DEFAULT_PRESET" ] || DEFAULT_PRESET="light_navy"

if [ "$PRESET_INPUT" = "auto" ]; then
  COLOR_PRESET="$DEFAULT_PRESET"
else
  COLOR_PRESET="$PRESET_INPUT"
fi
[ -n "$COLOR_PRESET" ] || COLOR_PRESET="light_navy"

echo "[1/4] Gemini 리서치 및 슬라이드 구조 생성..." >&2
GEMINI_TASK="gws-slides-${SLUG}"
GEMINI_PROMPT="[${TOPIC}]에 대한 ${SLIDE_N}장 프레젠테이션 슬라이드 구성을 JSON으로 만들어줘.
형식: {\"slides\": [{\"index\": 0, \"layout\": \"TITLE\", \"title\": \"...\", \"subtitle\": \"...\", \"body\": [], \"speaker_notes\": \"...\"}, ...]}
- index 0: 표지 (layout: TITLE, subtitle 포함)
- index 1~$((SLIDE_N - 2)): 본문 (layout: TITLE_AND_BODY, body 3~5개 항목)
- index $((SLIDE_N - 1)): 마무리 (layout: BLANK, 핵심 메시지)
반드시 유효한 JSON만 출력. 설명 없음."

bash "$ORCH" gemini "$GEMINI_PROMPT" "$GEMINI_TASK" >/dev/null

RESEARCH_LOG="$(ls -t "$LOG_DIR"/gemini_"$GEMINI_TASK"_*.txt 2>/dev/null | head -1 || true)"
if [ -z "$RESEARCH_LOG" ] || [ ! -f "$RESEARCH_LOG" ]; then
  GEMINI_RAW=""
else
  GEMINI_RAW="$(cat "$RESEARCH_LOG")"
fi

echo "[2/4] slide_data.json 생성..." >&2
GEMINI_RAW_TEXT="$GEMINI_RAW" python3 - "$TOPIC" "$TEMPLATE_ID" "$COLOR_PRESET" "$SLIDE_N" "$TMP_JSON" <<'PY'
import json
import os
import re
import sys

topic = sys.argv[1]
template_id = sys.argv[2].strip()
color_preset = sys.argv[3].strip() or "light_navy"
slide_n = int(sys.argv[4])
out_path = sys.argv[5]
raw = os.environ.get("GEMINI_RAW_TEXT", "")

allowed_layouts = {
    "TITLE",
    "TITLE_AND_BODY",
    "TITLE_AND_TWO_COLUMNS",
    "SECTION_HEADER",
    "MAIN_POINT",
    "BIG_NUMBER",
    "BLANK",
}


def normalize_slide(slide, index, total):
    if not isinstance(slide, dict):
        slide = {}
    title = str(slide.get("title", "")).strip() or f"슬라이드 {index + 1}"
    subtitle = str(slide.get("subtitle", "")).strip()
    body = slide.get("body", [])
    if isinstance(body, str):
        body = [x.strip() for x in body.splitlines() if x.strip()]
    if not isinstance(body, list):
        body = []
    body = [str(x).strip() for x in body if str(x).strip()]
    speaker_notes = str(slide.get("speaker_notes", "")).strip()

    layout = str(slide.get("layout", "")).strip().upper()
    if layout not in allowed_layouts:
        if index == 0:
            layout = "TITLE"
        elif index == total - 1:
            layout = "BLANK"
        else:
            layout = "TITLE_AND_BODY"

    return {
        "index": index,
        "layout": layout,
        "title": title,
        "subtitle": subtitle,
        "body": body,
        "speaker_notes": speaker_notes,
    }


def extract_balanced_json(text):
    start = text.find("{")
    while start != -1:
        depth = 0
        in_str = False
        esc = False
        for i in range(start, len(text)):
            ch = text[i]
            if in_str:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    in_str = False
                continue
            if ch == '"':
                in_str = True
                continue
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return text[start:i + 1]
        start = text.find("{", start + 1)
    return ""


def parse_slides(text):
    if not text.strip():
        return None
    fence = re.search(r"```json\s*(\{.*?\})\s*```", text, flags=re.S | re.I)
    candidate = fence.group(1) if fence else extract_balanced_json(text)
    if not candidate:
        return None
    data = json.loads(candidate)
    slides = data.get("slides") if isinstance(data, dict) else None
    if not isinstance(slides, list):
        return None
    return slides


def fallback_slides():
    total = 9
    slides = []
    for i in range(total):
        if i == 0:
            slides.append(
                {
                    "index": i,
                    "layout": "TITLE",
                    "title": topic,
                    "subtitle": "핵심 개요",
                    "body": [],
                    "speaker_notes": "",
                }
            )
        elif i == total - 1:
            slides.append(
                {
                    "index": i,
                    "layout": "BLANK",
                    "title": "결론",
                    "subtitle": "",
                    "body": ["핵심 메시지", "실행 포인트", "다음 단계"],
                    "speaker_notes": "",
                }
            )
        else:
            slides.append(
                {
                    "index": i,
                    "layout": "TITLE_AND_BODY",
                    "title": f"{topic} - 핵심 포인트 {i}",
                    "subtitle": "",
                    "body": ["핵심 항목 1", "핵심 항목 2", "핵심 항목 3"],
                    "speaker_notes": "",
                }
            )
    return slides


try:
    parsed = parse_slides(raw)
except Exception:
    parsed = None

if not parsed:
    parsed = fallback_slides()
    total = len(parsed)
else:
    total = max(1, slide_n)
    if len(parsed) < total:
        for i in range(len(parsed), total):
            parsed.append({"title": f"{topic} - 슬라이드 {i + 1}"})
    parsed = parsed[:total]

slides = [normalize_slide(s, i, len(parsed)) for i, s in enumerate(parsed)]

payload = {
    "topic": topic,
    "template_id": template_id if template_id else None,
    "color_preset": color_preset,
    "slides": slides,
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False, indent=2)
PY

if [ ! -f "$TMP_JSON" ]; then
  echo "[ERROR] slide_data.json 생성 실패" >&2
  exit 1
fi

echo "[3/4] Claude MCP로 Google Slides 생성..." >&2
SLIDE_JSON="$(cat "$TMP_JSON")"
PROMPT="다음 JSON 데이터로 Google Slides 프레젠테이션을 만들어줘.

규칙:
- template_id가 있으면 copy_drive_file로 복제 후 내용 교체
- template_id가 null이면 create_presentation으로 새로 생성
- 각 슬라이드는 layout에 맞는 predefinedLayout 사용 (createSlide)
- 제목은 첫 번째 텍스트박스, 본문은 두 번째 텍스트박스에 insertText
- body 항목은 줄바꿈(\\n)으로 연결해서 삽입
- speaker_notes도 각 슬라이드에 추가
- 완료 후 프레젠테이션 URL을 반드시 출력

JSON 데이터:
$SLIDE_JSON"

set +e
CLAUDE_OUT="$(unset CLAUDECODE; claude --allowedTools "mcp__google-workspace__*" -p "$PROMPT" 2>&1)"
CLAUDE_EXIT=$?
set -e

if [ $CLAUDE_EXIT -ne 0 ]; then
  echo "[ERROR] claude -p 실행 실패" >&2
  echo "$CLAUDE_OUT" >&2
  exit 1
fi

URL="$(printf '%s\n' "$CLAUDE_OUT" | grep -Eo 'https://docs\.google\.com/presentation/d/[A-Za-z0-9_-]+[^[:space:]]*' | head -1 || true)"
if [ -n "$URL" ]; then
  echo "[4/4] 완료" >&2
  echo "GWS: $URL"
else
  echo "[WARN] 프레젠테이션 URL을 찾지 못했습니다. claude 출력 원문:" >&2
  echo "$CLAUDE_OUT"
fi
