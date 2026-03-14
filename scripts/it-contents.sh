#!/usr/bin/env bash

set -euo pipefail

DRY_RUN=false

usage() {
  echo "Usage: bash it-contents.sh [--dry-run]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# IT 콘텐츠 전용 봇 토큰 우선 사용
if [[ -n "${TELEGRAM_BOT_TOKEN_IT:-}" ]]; then
  export TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN_IT"
fi
if [[ -n "${TELEGRAM_CHAT_ID_IT:-}" ]]; then
  export TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID_IT"
fi

BASE_DIR="$HOME/projects/agent-orchestration"
SCRIPTS_DIR="$BASE_DIR/scripts"
LOGS_DIR="$BASE_DIR/logs"
REPORTS_DIR="$BASE_DIR/reports"
TELEGRAM_SCRIPT="$SCRIPTS_DIR/telegram-send.sh"
ORCH_SCRIPT="$SCRIPTS_DIR/orchestrate.sh"

mkdir -p "$REPORTS_DIR"

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

send_telegram() {
  local msg="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    bash "$TELEGRAM_SCRIPT" --dry-run --message "$msg"
  else
    bash "$TELEGRAM_SCRIPT" --message "$msg"
  fi
}

fail() {
  local msg="$1"
  echo "[ERROR] $msg" >&2
  send_telegram "[IT 콘텐츠] 수집 실패: $msg" || true
  exit 1
}

[[ -x "$ORCH_SCRIPT" ]] || fail "orchestrate.sh를 찾을 수 없습니다: $ORCH_SCRIPT"
[[ -x "$TELEGRAM_SCRIPT" ]] || fail "telegram-send.sh를 찾을 수 없습니다: $TELEGRAM_SCRIPT"

RUN_DATE="$(date +%Y-%m-%d)"
SLUG="$(date +%Y%m%d_%H%M%S)"
REPORT_FILE="$REPORTS_DIR/it-contents-$RUN_DATE.md"
SENT_URLS_FILE="$REPORTS_DIR/it-contents-sent-urls.txt"
touch "$SENT_URLS_FILE"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RSS_ITEMS="$TMP_DIR/rss_items.tsv"
WEB_ITEMS="$TMP_DIR/web_items.tsv"
ALL_ITEMS="$TMP_DIR/all_items.tsv"
UNIQUE_ITEMS="$TMP_DIR/unique_items.tsv"
COLLECTED_LIST="$TMP_DIR/collected_list.txt"
SUMMARY_PROMPT="$TMP_DIR/summary_prompt.txt"
IMMEDIATE_ITEMS="$TMP_DIR/immediate.tsv"
LATER_ITEMS="$TMP_DIR/later.tsv"

touch "$RSS_ITEMS" "$WEB_ITEMS" "$ALL_ITEMS" "$UNIQUE_ITEMS" "$IMMEDIATE_ITEMS" "$LATER_ITEMS"

run_orchestrate() {
  local prompt="$1"
  local task_name="$2"
  local timeout_sec="${3:-180}"

  python3 - "$ORCH_SCRIPT" "$prompt" "$task_name" "$timeout_sec" <<'PYEOF'
import subprocess
import sys

orch_script, prompt, task_name, timeout_sec = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
try:
    subprocess.run(
        ["bash", orch_script, "gemini", prompt, task_name],
        cwd="/tmp",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=timeout_sec,
        check=True,
    )
except subprocess.TimeoutExpired:
    sys.exit(124)
except subprocess.CalledProcessError as e:
    sys.exit(e.returncode or 1)
PYEOF
}

latest_gemini_log() {
  local task_name="$1"
  ls -t "$LOGS_DIR"/gemini_"$task_name"_*.txt 2>/dev/null | head -1 || true
}

fetch_feed() {
  local source_name="$1"
  local feed_url="$2"
  local output_file="$3"
  local python_out
  if ! python_out="$(
    python3 - "$source_name" "$feed_url" <<'PYEOF'
import sys
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

source_name = sys.argv[1]
feed_url = sys.argv[2]

def node_text(elem, tag_names):
    for child in list(elem):
        tag = child.tag.split("}")[-1]
        if tag in tag_names:
            text = (child.text or "").strip()
            if text:
                return text
    return ""

def parse_dt(raw):
    raw = (raw or "").strip()
    if not raw:
        return None
    try:
        dt = parsedate_to_datetime(raw)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except Exception:
        pass
    try:
        if raw.endswith("Z"):
            raw = raw[:-1] + "+00:00"
        dt = datetime.fromisoformat(raw)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except Exception:
        return None

def atom_link(entry):
    for child in list(entry):
        if child.tag.split("}")[-1] != "link":
            continue
        href = child.attrib.get("href", "").strip()
        if href:
            return href
    return ""

req = urllib.request.Request(
    feed_url,
    headers={"User-Agent": "Mozilla/5.0 (it-contents-bot)"},
)
try:
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = resp.read()
except Exception as e:
    print(f"feed fetch error: {e}", file=sys.stderr)
    sys.exit(1)

try:
    root = ET.fromstring(data)
except Exception as e:
    print(f"feed parse error: {e}", file=sys.stderr)
    sys.exit(1)
now_utc = datetime.now(timezone.utc)
cutoff = now_utc - timedelta(hours=72)
rows = []

for elem in root.iter():
    tag = elem.tag.split("}")[-1]
    if tag not in ("item", "entry"):
        continue

    title = node_text(elem, {"title"})
    if not title:
        continue

    link = node_text(elem, {"link"})
    if not link and tag == "entry":
        link = atom_link(elem)
    if not link:
        continue

    raw_date = (
        node_text(elem, {"pubDate"})
        or node_text(elem, {"published"})
        or node_text(elem, {"updated"})
        or node_text(elem, {"date"})
    )
    dt = parse_dt(raw_date)
    if dt is None or dt < cutoff:
        continue

    date_text = dt.strftime("%Y-%m-%d %H:%M:%S %Z")
    title = " ".join(title.split())
    rows.append((source_name, title, link, date_text))

for row in rows:
    print("\t".join(row))
PYEOF
  )"; then
    return 1
  fi

  if [[ -n "$python_out" ]]; then
    printf '%s\n' "$python_out" >> "$output_file"
  fi
  return 0
}

collect_web_sources() {
  local task_name="it-contents-web-$SLUG"
  local prompt
  prompt=$(cat <<'PROMPT'
다음 사이트들에서 최근 3일 이내 발행된 글/영상 제목과 링크를 찾아줘:
- soylab AI: https://www.soylab.ai/
- 달파 블로그: https://app.dalpha.so/blog/
- litmers: https://litmers.com/blogs
- brunch 성대리: https://brunch.co.kr/@sungdairi
- 긱뉴스: https://news.hada.io
- 조코딩 유튜브: https://www.youtube.com/@jocoding
- bkamp_ai 유튜브: https://www.youtube.com/@bkamp_ai
- maker-evan 유튜브: https://www.youtube.com/@maker-evan
- ddokham 유튜브: https://www.youtube.com/@ddokham

없으면 최근 1주일 이내로 확장. 형식: 소스명 | 제목 | URL
PROMPT
)

  local run_ok=true
  if ! run_orchestrate "$prompt" "$task_name"; then
    run_ok=false
  fi

  local web_log
  web_log="$(latest_gemini_log "$task_name")"
  [[ -n "$web_log" ]] || fail "Gemini 웹검색 로그를 찾을 수 없습니다"
  if [[ "$run_ok" != "true" ]]; then
    echo "[WARN] Gemini 웹검색 호출 종료 지연/실패. 생성된 로그를 사용합니다: $web_log" >&2
  fi

  python3 - "$web_log" "$WEB_ITEMS" <<'PYEOF'
import re
import sys

log_path = sys.argv[1]
out_path = sys.argv[2]
pattern = re.compile(r'^\s*(?:[-*]\s*)?(.+?)\s*\|\s*(.+?)\s*\|\s*(https?://\S+)\s*$')

rows = []
with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
    for raw in f:
        line = raw.strip()
        m = pattern.match(line)
        if not m:
            continue
        source, title, url = [x.strip() for x in m.groups()]
        if source.startswith("[") and "]" in source:
            source = source.split("]", 1)[1].strip()
        if source and title and url:
            rows.append((source, title, url, "WEB"))

with open(out_path, "w", encoding="utf-8") as out:
    for row in rows:
        out.write("\t".join(row) + "\n")
PYEOF
}

summarize_items() {
  local task_name="it-contents-summary-$SLUG"
  cat > "$SUMMARY_PROMPT" <<'PROMPT'
다음 IT 콘텐츠 목록을 읽고 각 항목을 한 줄로 요약해줘.
[즉시읽기] / [나중에] 태그도 붙여줘.
기준:
- [즉시읽기]: AI 에이전트, LLM, 자동화, 실용 개발 팁, 트렌드
- [나중에]: 그 외

형식:
[즉시읽기] 소스명 | 제목 | 한줄요약 | URL
[나중에] 소스명 | 제목 | URL

목록:
PROMPT
  cat "$COLLECTED_LIST" >> "$SUMMARY_PROMPT"

  local run_ok=true
  if ! run_orchestrate "$(cat "$SUMMARY_PROMPT")" "$task_name"; then
    run_ok=false
  fi

  local summary_log
  summary_log="$(latest_gemini_log "$task_name")"
  [[ -n "$summary_log" ]] || fail "Gemini 통합 요약 로그를 찾을 수 없습니다"
  if [[ "$run_ok" != "true" ]]; then
    echo "[WARN] Gemini 통합 요약 호출 종료 지연/실패. 생성된 로그를 사용합니다: $summary_log" >&2
  fi

  python3 - "$summary_log" "$IMMEDIATE_ITEMS" "$LATER_ITEMS" <<'PYEOF'
import sys

log_path, immediate_path, later_path = sys.argv[1], sys.argv[2], sys.argv[3]

immediate = []
later = []

with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
    for raw in f:
        line = raw.strip()
        if line.startswith("- "):
            line = line[2:].strip()
        if not line.startswith("[즉시읽기]") and not line.startswith("[나중에]"):
            continue
        tag = "immediate" if line.startswith("[즉시읽기]") else "later"
        body = line.split("]", 1)[1].strip()
        parts = [p.strip() for p in body.split("|")]
        if tag == "immediate" and len(parts) >= 4:
            source, title = parts[0], parts[1]
            summary = "|".join(parts[2:-1]).strip()
            url = parts[-1]
            if source and title and url:
                immediate.append((source, title, summary, url))
        elif tag == "later" and len(parts) >= 3:
            source, title = parts[0], parts[1]
            url = parts[-1]
            if source and title and url:
                later.append((source, title, url))

with open(immediate_path, "w", encoding="utf-8") as f:
    for row in immediate:
        f.write("\t".join(row) + "\n")

with open(later_path, "w", encoding="utf-8") as f:
    for row in later:
        f.write("\t".join(row) + "\n")
PYEOF
}

collect_rss_sources() {
  local -a TISTORY_FEEDS=(
    "망나니개발자|https://mangkyu.tistory.com/rss"
    "twofootdog|https://twofootdog.tistory.com/rss"
    "bongman|https://bongman.tistory.com/rss"
    "조대협|https://bcho.tistory.com/rss"
  )
  local NAVER_FEED="SK C&C|https://rss.blog.naver.com/skcc_official.xml"

  local feed item source url

  for feed in "${TISTORY_FEEDS[@]}"; do
    source="${feed%%|*}"
    url="${feed#*|}"
    if ! fetch_feed "$source" "$url" "$RSS_ITEMS"; then
      echo "[WARN] RSS 수집 실패: $source ($url)" >&2
    fi
  done

  source="${NAVER_FEED%%|*}"
  url="${NAVER_FEED#*|}"
  if ! fetch_feed "$source" "$url" "$RSS_ITEMS"; then
    echo "[WARN] RSS 수집 실패: $source ($url)" >&2
  fi

}

collect_rss_sources
collect_web_sources

cat "$RSS_ITEMS" "$WEB_ITEMS" > "$ALL_ITEMS"

python3 - "$ALL_ITEMS" "$UNIQUE_ITEMS" "$SENT_URLS_FILE" <<'PYEOF'
import sys

in_path = sys.argv[1]
out_path = sys.argv[2]
sent_urls_path = sys.argv[3]

# 이미 전송한 URL 로드
with open(sent_urls_path, "r", encoding="utf-8", errors="ignore") as f:
    sent_urls = {line.strip() for line in f if line.strip()}

seen = set()
rows = []

with open(in_path, "r", encoding="utf-8", errors="ignore") as f:
    for raw in f:
        line = raw.strip()
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        source, title, url, date_text = [p.strip() for p in parts[:4]]
        key = (title, url)
        if key in seen:
            continue
        if url in sent_urls:
            continue
        seen.add(key)
        rows.append((source, title, url, date_text))

with open(out_path, "w", encoding="utf-8") as out:
    for row in rows:
        out.write("\t".join(row) + "\n")
PYEOF

TOTAL_COUNT=$(wc -l < "$UNIQUE_ITEMS" 2>/dev/null | tr -d ' ')

if [[ "$TOTAL_COUNT" -eq 0 ]]; then
  {
    echo "# IT 콘텐츠 — $RUN_DATE"
    echo
    echo "> 수집: 0개 항목 | 즉시읽기 0개 | 나중에 0개"
    echo
    echo "## 즉시읽기 (0개)"
    echo "- 없음"
    echo
    echo "## 나중에 (0개)"
    echo "- 없음"
  } > "$REPORT_FILE"

  send_telegram "[IT 콘텐츠] $RUN_DATE
오늘 새 항목 없음

📄 reports/it-contents-$RUN_DATE.md" || fail "텔레그램 알림 전송 실패"

  echo "[DONE] Report: $REPORT_FILE"
  echo "[DONE] No new items."
  exit 0
fi

awk -F '\t' '{ printf "%s | %s | %s\n", $1, $2, $3 }' "$UNIQUE_ITEMS" > "$COLLECTED_LIST"

summarize_items

IMMEDIATE_COUNT=$(wc -l < "$IMMEDIATE_ITEMS" 2>/dev/null | tr -d ' ')
LATER_COUNT=$(wc -l < "$LATER_ITEMS" 2>/dev/null | tr -d ' ')

if [[ "$IMMEDIATE_COUNT" -eq 0 && "$LATER_COUNT" -eq 0 ]]; then
  fail "Gemini 요약 결과 파싱 실패"
fi

{
  echo "# IT 콘텐츠 — $RUN_DATE"
  echo
  echo "> 수집: ${TOTAL_COUNT}개 항목 | 즉시읽기 ${IMMEDIATE_COUNT}개 | 나중에 ${LATER_COUNT}개"
  echo
  echo "## 즉시읽기 (${IMMEDIATE_COUNT}개)"
  if [[ "$IMMEDIATE_COUNT" -gt 0 ]]; then
    while IFS=$'\t' read -r source title summary url; do
      [[ -z "${source:-}" ]] && continue
      echo "- **$source** | [$title]($url)"
      if [[ -n "${summary:-}" ]]; then
        echo "  $summary"
      fi
      echo
    done < "$IMMEDIATE_ITEMS"
  else
    echo "- 없음"
    echo
  fi

  echo "## 나중에 (${LATER_COUNT}개)"
  if [[ "$LATER_COUNT" -gt 0 ]]; then
    while IFS=$'\t' read -r source title url; do
      [[ -z "${source:-}" ]] && continue
      echo "- **$source** | [$title]($url)"
    done < "$LATER_ITEMS"
  else
    echo "- 없음"
  fi
} > "$REPORT_FILE"

TELEGRAM_PREVIEW="$TMP_DIR/telegram_preview.txt"
if [[ "$IMMEDIATE_COUNT" -gt 0 ]]; then
  head -n 5 "$IMMEDIATE_ITEMS" | while IFS=$'\t' read -r source title summary _url; do
    [[ -z "${source:-}" ]] && continue
    echo "• $source | $title"
    if [[ -n "${summary:-}" ]]; then
      echo "  $summary"
    fi
    echo ""
  done > "$TELEGRAM_PREVIEW"
else
  echo "• 즉시읽기 항목 없음" > "$TELEGRAM_PREVIEW"
fi

TELEGRAM_MESSAGE="[IT 콘텐츠] $RUN_DATE
즉시읽기 ${IMMEDIATE_COUNT}개 | 나중에 ${LATER_COUNT}개

$(cat "$TELEGRAM_PREVIEW")
💬 Claude Code에 붙여넣기:
  \"/it-contents 읽어줘\"
📄 reports/it-contents-$RUN_DATE.md"

send_telegram "$TELEGRAM_MESSAGE" || fail "텔레그램 알림 전송 실패"

# 전송 완료된 URL 기록 (dry-run 제외)
if [[ "$DRY_RUN" == "false" ]]; then
  awk -F '\t' '{print $3}' "$UNIQUE_ITEMS" >> "$SENT_URLS_FILE"
  # 30일치만 유지 (오래된 URL 제거)
  python3 - "$SENT_URLS_FILE" <<'PYEOF'
import sys, os
from datetime import datetime, timedelta
path = sys.argv[1]
with open(path) as f:
    lines = [l.strip() for l in f if l.strip()]
# URL은 날짜 정보 없이 저장되므로 최근 5000개만 유지
lines = lines[-5000:]
with open(path, "w") as f:
    f.write("\n".join(lines) + "\n" if lines else "")
PYEOF
fi

# vault 저장
if [[ "$DRY_RUN" == "false" ]]; then
  VAULT_DIR="$HOME/vault/10-knowledge/research"
  mkdir -p "$VAULT_DIR"
  VAULT_FILE="$VAULT_DIR/it-contents-$RUN_DATE.md"
  {
    printf -- "---\ntype: research\ndomain: it-contents\nsource: it-contents\ndate: %s\nstatus: done\n---\n\n" "$RUN_DATE"
    cat "$REPORT_FILE"
  } > "$VAULT_FILE"
  echo "[VAULT] Saved → $VAULT_FILE"
fi

echo "[DONE] Report: $REPORT_FILE"
echo "[DONE] Total: $TOTAL_COUNT | Immediate: $IMMEDIATE_COUNT | Later: $LATER_COUNT"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY-RUN] Telegram message was not sent."
fi
