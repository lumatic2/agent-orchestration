#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$BASE_DIR/data"
LOG_DIR="$BASE_DIR/logs"
DATA_FILE="$DATA_DIR/latest-topics.json"
TELEGRAM_SCRIPT="$SCRIPT_DIR/telegram-send.sh"

# Load secrets: GCP Secret Manager -> .env fallback
_S="$SCRIPT_DIR/secrets_load.sh"
# shellcheck disable=SC1090
[ -f "$_S" ] && source "$_S" 2>/dev/null
unset _S

# Content chat routing
if [[ -n "${TELEGRAM_BOT_TOKEN_IT:-}" ]]; then
  export TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN_IT"
fi
if [[ -n "${TELEGRAM_CHAT_ID_CONTENT:-}" ]]; then
  export TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID_CONTENT"
fi

mkdir -p "$DATA_DIR" "$LOG_DIR"

[[ -x "$TELEGRAM_SCRIPT" ]] || {
  echo "[ERROR] telegram-send.sh not found: $TELEGRAM_SCRIPT" >&2
  exit 1
}

export PATH="/Users/luma3/.nvm/versions/node/v24.14.0/bin:$PATH"
GEMINI_BIN_DEFAULT="/Users/luma3/.nvm/versions/node/v24.14.0/bin/gemini"
if [[ -x "${GEMINI_BIN:-$GEMINI_BIN_DEFAULT}" ]]; then
  GEMINI_CMD="${GEMINI_BIN:-$GEMINI_BIN_DEFAULT}"
else
  GEMINI_CMD="gemini"
fi

RUN_DATE="$(date +%Y-%m-%d)"
TMP_RAW="$(mktemp)"
TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_RAW" "$TMP_JSON"' EXIT

PROMPT=$(cat <<'EOF'
한국어 유튜브 채널용 주제 제목 10개를 제안해줘.

## 채널 정체성
- "AI 시대, 나는 이렇게 살고 있다" — 비개발자 실무자의 AI 라이프스타일 채널
- 도구 소개가 아닌 실제 경험담·패턴·인사이트 중심
- 톤: 담담하고 실용적, 과장/낚시 금지

## 다루는 영역 (매 회차마다 골고루 섞어라)
- 🤖 AI 워크플로우·자동화 (Claude, Gemini, Codex 실전 활용)
- 🎵 AI x 음악 (Suno로 작곡, BGM 제작, 음향 디자인)
- 🎨 AI x 디자인 (Midjourney, Firefly, Canva AI 실제 작업)
- 🍽️ AI x 미식·요리 (레시피 생성, 식재료 관리, 맛집 큐레이션)
- 🔊 AI x 음향·사운드 (ElevenLabs, 팟캐스트, 보이스 제작)
- 🐾 AI x 반려동물 (건강 관리, 행동 분석, 케어 자동화)
- 💡 기타 라이프스타일 (여행, 독서, 인테리어 등 AI 접목)

## 조건
- 타깃: AI를 일상·취미에 적용하려는 성인 (비개발자)
- 톤 비중: 진지 5 : 가벼움 5
- 10개 중 AI 워크플로우 3개, 나머지 영역에서 7개 분산
- 제목은 짧고 호기심을 자극하되 낚시성 금지
- "내가 해봤더니" "써봤다" 등 1인칭 경험 톤 권장

출력 형식:
JSON만 출력.
{
  "topics": ["제목1", "제목2", ... 정확히 10개]
}
EOF
)

if ! "$GEMINI_CMD" --yolo -m gemini-2.5-flash -p "$PROMPT" >"$TMP_RAW" 2>&1; then
  bash "$TELEGRAM_SCRIPT" --message "[유튜브 주제] ${RUN_DATE} 생성 실패" || true
  echo "[ERROR] Gemini call failed." >&2
  cat "$TMP_RAW" >&2
  exit 1
fi

if ! python3 - "$RUN_DATE" "$TMP_RAW" "$TMP_JSON" <<'PYEOF'
import json
import re
import sys
from pathlib import Path
from typing import Optional

run_date = sys.argv[1]
raw_path = Path(sys.argv[2])
out_path = Path(sys.argv[3])
text = raw_path.read_text(encoding="utf-8", errors="ignore")


def extract_json_block(src: str) -> Optional[str]:
    stripped = src.strip()
    if stripped.startswith("{") and stripped.endswith("}"):
        return stripped

    m = re.search(r"```(?:json)?\s*(\{[\s\S]*?\})\s*```", src)
    if m:
        return m.group(1).strip()

    start = src.find("{")
    end = src.rfind("}")
    if start != -1 and end != -1 and end > start:
        return src[start : end + 1].strip()
    return None


def normalize_topic(line: str) -> str:
    s = re.sub(r"^\s*(?:\d{1,2}[.)]|[-*•])\s*", "", line.strip())
    s = s.strip().strip('"').strip("'")
    return s


topics = []
block = extract_json_block(text)
if block:
    try:
        parsed = json.loads(block)
        if isinstance(parsed, dict):
            arr = parsed.get("topics", [])
        elif isinstance(parsed, list):
            arr = parsed
        else:
            arr = []
        for item in arr:
            if isinstance(item, str):
                t = item.strip()
                if t:
                    topics.append(t)
    except Exception:
        pass

if not topics:
    for raw_line in text.splitlines():
        line = normalize_topic(raw_line)
        if not line:
            continue
        if len(line) > 120:
            continue
        topics.append(line)

seen = set()
deduped = []
for t in topics:
    if t in seen:
        continue
    seen.add(t)
    deduped.append(t)
    if len(deduped) == 10:
        break

if not deduped:
    raise SystemExit("No topics parsed from Gemini response")

payload = {"date": run_date, "topics": deduped}
out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
PYEOF
then
  bash "$TELEGRAM_SCRIPT" --message "[유튜브 주제] ${RUN_DATE} 파싱 실패" || true
  echo "[ERROR] Failed to parse Gemini output into topics JSON." >&2
  cat "$TMP_RAW" >&2
  exit 1
fi
cp "$TMP_JSON" "$DATA_FILE"

TOPICS_MESSAGE="$(
python3 - "$DATA_FILE" "$RUN_DATE" <<'PYEOF'
import json
import sys
from pathlib import Path

data_file = Path(sys.argv[1])
run_date = sys.argv[2]
data = json.loads(data_file.read_text(encoding="utf-8"))
topics = data.get("topics", [])
lines = [f"[유튜브 주제 추천] {run_date}"]
for i, topic in enumerate(topics, 1):
    lines.append(f"{i}. {topic}")
print("\n".join(lines))
PYEOF
)"

bash "$TELEGRAM_SCRIPT" --message "$TOPICS_MESSAGE"
echo "[OK] Saved: $DATA_FILE"
