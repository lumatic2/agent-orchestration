#!/usr/bin/env bash

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

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
  echo "Usage: bash slides-bridge.sh [--dry-run] \"주제명\" [슬라이드수=9] [출력=local]" >&2
  echo "출력 옵션: local | telegram | notion" >&2
  exit 1
fi

TOPIC="$1"
SLIDE_N="${2:-9}"
OUTPUT="${3:-local}"

if ! [[ "$SLIDE_N" =~ ^[0-9]+$ ]]; then
  echo "[ERROR] 슬라이드 수는 숫자여야 합니다: $SLIDE_N" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
GEN_BRIEF="$SCRIPT_DIR/gen-brief.sh"
ORCH="$SCRIPT_DIR/orchestrate.sh"
RENDER="$SCRIPT_DIR/render-slides.sh"
LOG_DIR="$REPO_DIR/logs"

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^[:alnum:]가-힣]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

if [ "$dry_run" = true ]; then
  DRY_SLUG="$(slugify "$TOPIC")"
  [ -n "$DRY_SLUG" ] || DRY_SLUG="slides"
  DRY_HTML="/tmp/${DRY_SLUG}.html"
  DRY_PDF="$HOME/Desktop/${DRY_SLUG}.pdf"

  echo "[1/5] 브리프 생성 중: ${TOPIC}" >&2
  echo "[DRY-RUN] bash \"$GEN_BRIEF\" \"$TOPIC\" \"$SLIDE_N\"" >&2
  echo "[2/5] Gemini 리서치 중..." >&2
  echo "[DRY-RUN] bash \"$ORCH\" gemini \"...\" \"slides-research-${DRY_SLUG}\"" >&2
  echo "[3/5] 브리프 조립 중..." >&2
  echo "[DRY-RUN] python3 (brief + research -> /tmp/${DRY_SLUG}-codex-brief.md, HTML: ${DRY_HTML})" >&2
  echo "[4/5] Codex HTML 생성 중..." >&2
  echo "[DRY-RUN] bash \"$ORCH\" codex \"@/tmp/${DRY_SLUG}-codex-brief.md\" \"slides-html-${DRY_SLUG}\"" >&2
  echo "[5/5] PDF 렌더 중..." >&2
  echo "[DRY-RUN] bash \"$RENDER\" \"$DRY_HTML\" \"$DRY_SLUG\"" >&2
  echo "[DRY-RUN] output target: $OUTPUT" >&2
  echo "PDF: $DRY_PDF"
  exit 0
fi

echo "[1/5] 브리프 생성 중: ${TOPIC}" >&2
brief_output="$(bash "$GEN_BRIEF" "$TOPIC" "$SLIDE_N")"
BRIEF_FILE="$(echo "$brief_output" | grep '^BRIEF:' | awk '{print $2}')"
PRESET="$(echo "$brief_output" | grep '^PRESET:' | awk '{print $2}')"

if [ -z "${BRIEF_FILE:-}" ] || [ ! -f "$BRIEF_FILE" ]; then
  echo "[ERROR] BRIEF 파일 생성 실패" >&2
  exit 1
fi

SLUG="$(basename "$BRIEF_FILE" -brief.md)"
[ -n "$SLUG" ] || SLUG="$(slugify "$TOPIC")"
[ -n "$SLUG" ] || SLUG="slides"

echo "[2/5] Gemini 리서치 중..." >&2
TASK_NAME="slides-research-$SLUG"
RESEARCH_PROMPT=$'주제 ['"$TOPIC"$']에 대한 슬라이드 '"$SLIDE_N"$'장 분량 리서치.\n\n다음 형식으로 각 슬라이드의 핵심 내용을 제안해줘:\nS1: [타이틀 슬라이드] 부제, 핵심 포인트 3개\nS2: [섹션명] badge텍스트, 제목, 핵심내용 4~6개\nS3: [섹션명] badge텍스트, 제목, 비교항목(표 형식)\nS4~S8: 각각 badge, 제목, 내용 요약\nS9: [결론] 핵심 메시지 1문장, 3가지 실행 포인트\n\n슬라이드별 내용은 구체적인 데이터, 숫자, 사례 포함.'
bash "$ORCH" gemini "$RESEARCH_PROMPT" "$TASK_NAME"

RESEARCH_LOG="$(ls -t "$LOG_DIR"/gemini_slides-research-"$SLUG"_*.txt 2>/dev/null | head -1 || true)"
if [ -z "${RESEARCH_LOG:-}" ]; then
  echo "[WARN] Gemini 리서치 결과를 찾을 수 없음. 브리프 구조만으로 진행." >&2
  RESEARCH_CONTENT="리서치 결과 없음. 주제: $TOPIC"
else
  RESEARCH_CONTENT="$(grep -vE '^(YOLO|Loaded|Error|Attempt|Retrying|$)' "$RESEARCH_LOG" | head -200 || true)"
  if [ -z "${RESEARCH_CONTENT:-}" ]; then
    RESEARCH_CONTENT="리서치 결과 없음. 주제: $TOPIC"
  fi
fi

echo "[3/5] 브리프 조립 중..." >&2
CODEX_BRIEF="/tmp/${SLUG}-codex-brief.md"
HTML_PATH="$(
  BRIEF_FILE="$BRIEF_FILE" \
  CODEX_BRIEF_FILE="$CODEX_BRIEF" \
  SLUG="$SLUG" \
  RESEARCH_CONTENT="$RESEARCH_CONTENT" \
  python3 - <<'PY'
import os
import re

brief_file = os.environ["BRIEF_FILE"]
codex_brief_file = os.environ["CODEX_BRIEF_FILE"]
slug = os.environ["SLUG"]
research = os.environ.get("RESEARCH_CONTENT", "")

with open(brief_file, encoding="utf-8") as f:
    brief = f.read()

lines = research.splitlines()
slot_map = {}
current_slot = None
for line in lines:
    m = re.match(r"^\s*S(\d+)\s*:\s*(.*)$", line)
    if m:
        current_slot = f"S{m.group(1)}"
        slot_map[current_slot] = m.group(2).strip()
        continue
    if current_slot and line.strip():
        if slot_map[current_slot]:
            slot_map[current_slot] += "\n" + line.strip()
        else:
            slot_map[current_slot] = line.strip()

for slot, content in slot_map.items():
    if not content.strip():
        continue
    summary = content.strip().replace("\n", " ")
    if len(summary) > 50:
        summary = summary[:50] + "..."
    header_pattern = re.compile(
        rf"^(###\s+{re.escape(slot)}\s+—\s*)(TODO)(\s*\[.*\])$",
        re.MULTILINE,
    )
    brief = header_pattern.sub(rf"\1{summary}\3", brief)
    section_pattern = re.compile(
        rf"(^###\s+{re.escape(slot)}\s+—[^\n]*\n)",
        re.MULTILINE,
    )
    if section_pattern.search(brief):
        insert_text = "\\1- 리서치 반영:\n" + "\n".join(
            [f"  - {x}" for x in content.split("\n") if x.strip()]
        ) + "\n"
        brief = section_pattern.sub(insert_text, brief, count=1)

html_path = f"/tmp/{slug}.html"
brief = brief.rstrip() + f"\n\n## HTML 저장 경로\n{html_path}\n"
instruction = (
    "아래 브리프를 따라 1280x720 HTML 슬라이드 9장을 생성하고, "
    f"반드시 {html_path} 에 저장하세요.\n"
    "응답에는 설명 없이 파일 생성 작업만 수행하세요.\n\n"
)
brief = instruction + brief

with open(codex_brief_file, "w", encoding="utf-8") as f:
    f.write(brief)

print(html_path)
PY
)"

if [ -z "${HTML_PATH:-}" ]; then
  echo "[ERROR] 브리프 조립 실패: HTML 경로 생성 실패" >&2
  exit 1
fi

echo "[4/5] Codex HTML 생성 중..." >&2
TASK_NAME2="slides-html-$SLUG"
bash "$ORCH" codex "@$CODEX_BRIEF" "$TASK_NAME2"

if [ ! -f "$HTML_PATH" ]; then
  echo "[ERROR] HTML 생성 실패: $HTML_PATH" >&2
  exit 1
fi

echo "[5/5] PDF 렌더 중..." >&2
OUTPUT_NAME="$SLUG"
bash "$RENDER" "$HTML_PATH" "$OUTPUT_NAME"
PDF_PATH="$HOME/Desktop/${OUTPUT_NAME}.pdf"

case "$OUTPUT" in
  telegram)
    if [ -f "$SCRIPT_DIR/telegram-send.sh" ]; then
      bash "$SCRIPT_DIR/telegram-send.sh" "$PDF_PATH" "✅ 슬라이드 생성 완료: $TOPIC"
    else
      echo "[INFO] telegram-send.sh 미설치. PDF 경로: $PDF_PATH" >&2
    fi
    ;;
  notion)
    if [ -f "$SCRIPT_DIR/notion-upload.sh" ]; then
      bash "$SCRIPT_DIR/notion-upload.sh" "$PDF_PATH" "$TOPIC"
    else
      echo "[INFO] notion-upload.sh 미설치. PDF 경로: $PDF_PATH" >&2
    fi
    ;;
  local|*)
    echo "[OK] PDF 저장: $PDF_PATH"
    ;;
esac

echo "PDF: $PDF_PATH"
