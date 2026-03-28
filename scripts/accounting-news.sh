#!/usr/bin/env bash

set -euo pipefail

# Load secrets: GCP Secret Manager -> .env fallback
_S="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/secrets_load.sh"
# shellcheck disable=SC1090
[ -f "$_S" ] && source "$_S" 2>/dev/null; unset _S

DRY_RUN=false

usage() {
  echo "Usage: bash accounting-news.sh [--dry-run]"
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

# 회계 뉴스 전용 환경변수 오버라이드
if [[ -n "${TELEGRAM_BOT_TOKEN_IT:-}" ]]; then
  export TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN_IT"
fi
if [[ -n "${TELEGRAM_CHAT_ID_ACCOUNTING:-}" ]]; then
  export TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID_ACCOUNTING"
fi

BASE_DIR="$HOME/projects/agent-orchestration"
SCRIPTS_DIR="$BASE_DIR/scripts"
LOGS_DIR="$BASE_DIR/logs"
REPORTS_DIR="$BASE_DIR/reports"
TELEGRAM_SCRIPT="$SCRIPTS_DIR/telegram-send.sh"
ORCH_SCRIPT="$SCRIPTS_DIR/orchestrate.sh"

mkdir -p "$REPORTS_DIR"

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
  send_telegram "[회계 뉴스] 수집 실패: $msg" || true
  exit 1
}

[[ -x "$ORCH_SCRIPT" ]] || fail "orchestrate.sh를 찾을 수 없습니다: $ORCH_SCRIPT"
[[ -x "$TELEGRAM_SCRIPT" ]] || fail "telegram-send.sh를 찾을 수 없습니다: $TELEGRAM_SCRIPT"

RUN_DATE="$(date +%Y-%m-%d)"
SLUG="$(date +%Y%m%d_%H%M%S)"
REPORT_FILE="$REPORTS_DIR/accounting-news-$RUN_DATE.md"
SENT_URLS_FILE="$REPORTS_DIR/accounting-news-sent-urls.txt"
touch "$SENT_URLS_FILE"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RSS_ITEMS="$TMP_DIR/rss_items.tsv"
WEB_ITEMS="$TMP_DIR/web_items.tsv"
ALL_ITEMS="$TMP_DIR/all_items.tsv"
UNIQUE_ITEMS="$TMP_DIR/unique_items.tsv"
COLLECTED_LIST="$TMP_DIR/collected_list.txt"
SUMMARY_PROMPT="$TMP_DIR/summary_prompt.txt"
CATEGORIZED_ITEMS="$TMP_DIR/categorized.tsv"
OVERVIEW_FILE="$TMP_DIR/overview.txt"
TELEGRAM_MESSAGE_FILE="$TMP_DIR/telegram_message.html"
COUNTS_LINE_FILE="$TMP_DIR/counts_line.txt"

touch "$RSS_ITEMS" "$WEB_ITEMS" "$ALL_ITEMS" "$UNIQUE_ITEMS" "$CATEGORIZED_ITEMS" "$OVERVIEW_FILE" "$COUNTS_LINE_FILE"

run_orchestrate() {
  local prompt="$1"
  local task_name="$2"
  local timeout_sec="${3:-180}"

  python3 - "$ORCH_SCRIPT" "$prompt" "$task_name" "$timeout_sec" <<'PYEOF'
import subprocess
import sys

orch_script, prompt, task_name, timeout_sec = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
try:
    import os
    env = os.environ.copy()
    env["NO_VAULT"] = env.get("NO_VAULT", "false")
    subprocess.run(
        ["bash", orch_script, "gemini", prompt, task_name],
        cwd="/tmp",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=timeout_sec,
        check=True,
        env=env,
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
    headers={"User-Agent": "Mozilla/5.0 (accounting-news-bot)"},
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

collect_rss_sources() {
  local -a ALL_FEEDS=(
    "Google 뉴스(회계 세무)|https://news.google.com/rss/search?q=%ED%9A%8C%EA%B3%84+%EC%84%B8%EB%AC%B4&hl=ko&gl=KR&ceid=KR:ko"
    "Google 뉴스(국세청 세법 개정)|https://news.google.com/rss/search?q=%EA%B5%AD%EC%84%B8%EC%B2%AD+%EC%84%B8%EB%B2%95+%EA%B0%9C%EC%A0%95&hl=ko&gl=KR&ceid=KR:ko"
    "Google 뉴스(KICPA)|https://news.google.com/rss/search?q=KICPA+%EA%B3%B5%EC%9D%B8%ED%9A%8C%EA%B3%84%EC%82%AC&hl=ko&gl=KR&ceid=KR:ko"
    "Google 뉴스(세무사 시험)|https://news.google.com/rss/search?q=%EC%84%B8%EB%AC%B4%EC%82%AC+%EC%8B%9C%ED%97%98+%ED%95%A9%EA%B2%A9&hl=ko&gl=KR&ceid=KR:ko"
  )

  local feed source url
  for feed in "${ALL_FEEDS[@]}"; do
    source="${feed%%|*}"
    url="${feed#*|}"
    if ! fetch_feed "$source" "$url" "$RSS_ITEMS"; then
      echo "[WARN] RSS 수집 실패: $source ($url)" >&2
    fi
  done
}

collect_web_sources() {
  local task_name="acc-news-web-$SLUG"
  local prompt
  prompt=$(cat <<'PROMPT'
다음 사이트들에서 최근 3일 이내 게시된 공지·뉴스 제목과 링크를 찾아줘:
- 국세청 공지사항: https://www.nts.go.kr/nts/cm/cntnts/cntntsView.do?mi=2272&cntntsId=7692
- 금감원 회계기준 변경: https://www.fss.or.kr/fss/main/main.do
- 한국세무사회: https://www.kacpta.or.kr
- KICPA 공식 뉴스: https://www.kicpa.or.kr

없으면 최근 1주일로 확장. 형식: 소스명 | 제목 | URL
PROMPT
)

  local run_ok=true
  if ! NO_VAULT=true run_orchestrate "$prompt" "$task_name"; then
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
  local task_name="acc-news-summary-$SLUG"
  cat > "$SUMMARY_PROMPT" <<'PROMPT'
다음은 오늘 수집된 회계/세무 뉴스 목록이다.
각 항목을 아래 카테고리 중 하나로 분류하고, 한 줄 요약을 붙여줘.

카테고리: [세법변경] [수험정보] [업계동향] [AI자동화] [Planby관련]
Planby관련 판단 기준: 스타트업 재무/세무, AI SaaS 회계처리, 창업 세무 관련

출력 형식 (탭 구분):
카테고리\t소스\t제목\t한줄요약\tURL

항목 목록:
PROMPT
  cat "$COLLECTED_LIST" >> "$SUMMARY_PROMPT"

  local run_ok=true
  if ! NO_VAULT=true run_orchestrate "$(cat "$SUMMARY_PROMPT")" "$task_name"; then
    run_ok=false
  fi

  local summary_log
  summary_log="$(latest_gemini_log "$task_name")"
  [[ -n "$summary_log" ]] || fail "Gemini 분류/요약 로그를 찾을 수 없습니다"
  if [[ "$run_ok" != "true" ]]; then
    echo "[WARN] Gemini 분류/요약 호출 종료 지연/실패. 생성된 로그를 사용합니다: $summary_log" >&2
  fi

  python3 - "$summary_log" "$CATEGORIZED_ITEMS" <<'PYEOF'
import re
import sys

log_path, out_path = sys.argv[1], sys.argv[2]
allowed = {"세법변경", "수험정보", "업계동향", "AI자동화", "Planby관련"}
rows = []

with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
    for raw in f:
        line = raw.strip()
        if not line:
            continue
        if line.startswith("- "):
            line = line[2:].strip()
        parts = [p.strip() for p in line.split("\t")]
        if len(parts) < 5:
            continue

        cat = re.sub(r"^[`\s]*\[?(.*?)\]?[`\s]*$", r"\1", parts[0]).strip()
        if cat not in allowed:
            continue

        source = parts[1]
        title = parts[2]
        summary = parts[3]
        url = parts[4]

        if not source or not title or not summary or not url.startswith("http"):
            continue

        rows.append((cat, source, title, summary, url))

with open(out_path, "w", encoding="utf-8") as out:
    for row in rows:
        out.write("\t".join(row) + "\n")
PYEOF
}

generate_overview() {
  local task_name="acc-news-overview-$SLUG"
  local overview_prompt="$TMP_DIR/overview_prompt.txt"

  {
    cat <<'PROMPT'
오늘 회계/세무 뉴스를 바탕으로:
1. 오늘의 핵심 업계 변화 1줄
2. AI가 회계/세무 업계에 미치는 영향 1줄 (없으면 생략)
3. Planby(AI 건축설계 SaaS 스타트업) 재무/세무 영향 1줄

간결하게, 각 항목 앞에 번호 포함. 총 2-3줄.

뉴스 목록:
PROMPT
    cat "$COLLECTED_LIST"
  } > "$overview_prompt"

  local run_ok=true
  if ! NO_VAULT=true run_orchestrate "$(cat "$overview_prompt")" "$task_name" 120; then
    run_ok=false
  fi

  local overview_log
  overview_log="$(latest_gemini_log "$task_name")"
  if [[ -z "$overview_log" ]]; then
    echo "[WARN] Gemini 종합 인사이트 로그 없음, 스킵" >&2
    return 0
  fi
  if [[ "$run_ok" != "true" ]]; then
    echo "[WARN] Gemini 종합 인사이트 호출 종료 지연. 생성된 로그 사용: $overview_log" >&2
  fi

  python3 - "$overview_log" "$OVERVIEW_FILE" <<'PYEOF'
import re
import sys

log_path, out_path = sys.argv[1], sys.argv[2]
lines = []

with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
    for raw in f:
        line = raw.strip()
        if not line:
            continue
        if re.match(r'^\s*(---|===|```)', line):
            continue
        if re.match(r'^\d+[.)]\s+', line):
            lines.append(line)
            continue
        if line.startswith(("1.", "2.", "3.")):
            lines.append(line)
            continue

seen = []
for line in lines:
    if line not in seen:
        seen.append(line)

with open(out_path, "w", encoding="utf-8") as f:
    if seen:
        f.write("\n".join(seen[:3]) + "\n")
PYEOF
}

collect_rss_sources
collect_web_sources

cat "$RSS_ITEMS" "$WEB_ITEMS" > "$ALL_ITEMS"

python3 - "$ALL_ITEMS" "$UNIQUE_ITEMS" "$SENT_URLS_FILE" <<'PYEOF'
import sys

in_path = sys.argv[1]
out_path = sys.argv[2]
sent_urls_path = sys.argv[3]

with open(sent_urls_path, "r", encoding="utf-8", errors="ignore") as f:
    sent_urls = set()
    for line in f:
        line = line.strip()
        if not line:
            continue
        parts = line.split(' ', 1)
        sent_urls.add(parts[1] if len(parts) == 2 else parts[0])

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
    echo "# 회계 뉴스 — $RUN_DATE"
    echo
    echo "> 수집: 0개 항목"
    echo
    echo "오늘 새 항목 없음"
  } > "$REPORT_FILE"

  send_telegram "[회계 뉴스] $RUN_DATE
오늘 새 항목 없음" || fail "텔레그램 알림 전송 실패"

  echo "[DONE] Report: $REPORT_FILE"
  echo "[DONE] No new items."
  exit 0
fi

awk -F '\t' '{ printf "%s | %s | %s\n", $1, $2, $3 }' "$UNIQUE_ITEMS" > "$COLLECTED_LIST"

summarize_items
generate_overview

CATEGORIZED_COUNT=$(wc -l < "$CATEGORIZED_ITEMS" 2>/dev/null | tr -d ' ')
if [[ "$CATEGORIZED_COUNT" -eq 0 ]]; then
  fail "Gemini 분류 결과 파싱 실패"
fi

python3 - "$CATEGORIZED_ITEMS" "$COUNTS_LINE_FILE" "$TELEGRAM_MESSAGE_FILE" "$OVERVIEW_FILE" "$RUN_DATE" <<'PYEOF'
import html
import sys
from collections import OrderedDict, defaultdict

categorized_path, counts_path, message_path, overview_path, run_date = sys.argv[1:6]
order = ["세법변경", "수험정보", "업계동향", "AI자동화", "Planby관련"]
icons = {
    "세법변경": "🔴",
    "수험정보": "📚",
    "업계동향": "📊",
    "AI자동화": "🤖",
    "Planby관련": "🏢",
}

data = defaultdict(list)
with open(categorized_path, "r", encoding="utf-8", errors="ignore") as f:
    for raw in f:
        p = raw.rstrip("\n").split("\t")
        if len(p) < 5:
            continue
        cat, source, title, summary, url = p[:5]
        if cat in order:
            data[cat].append((source, title, summary, url))

counts = [f"{cat} {len(data[cat])}개" for cat in order if len(data[cat]) > 0]
counts_line = " | ".join(counts) if counts else "분류 결과 없음"

with open(counts_path, "w", encoding="utf-8") as f:
    f.write(counts_line + "\n")

overview = ""
with open(overview_path, "r", encoding="utf-8", errors="ignore") as f:
    overview = f.read().strip()
if not overview:
    overview = "1. 오늘 핵심 변경사항 파악을 위한 추가 분석 필요"

parts = [
    f"[회계 뉴스] {run_date}",
    counts_line,
    "",
    "<b>📋 오늘의 인사이트</b>",
    html.escape(overview),
]

for cat in order:
    items = data[cat]
    if not items:
        continue
    parts.append("")
    parts.append(f"<b>{icons[cat]} {cat}</b>")
    for _, title, summary, url in items:
        parts.append(f"• <a href=\"{html.escape(url, quote=True)}\">{html.escape(title)}</a>")
        parts.append(f"  {html.escape(summary)}")

with open(message_path, "w", encoding="utf-8") as f:
    f.write("\n".join(parts).strip() + "\n")
PYEOF

COUNTS_LINE="$(cat "$COUNTS_LINE_FILE")"

{
  echo "# 회계 뉴스 — $RUN_DATE"
  echo
  echo "> 수집: ${TOTAL_COUNT}개 항목 | ${COUNTS_LINE}"
  echo
  echo "## 오늘의 인사이트"
  if [[ -s "$OVERVIEW_FILE" ]]; then
    cat "$OVERVIEW_FILE"
  else
    echo "1. 오늘 핵심 변경사항 파악을 위한 추가 분석 필요"
  fi

  local_order=("세법변경" "수험정보" "업계동향" "AI자동화" "Planby관련")
  for cat in "${local_order[@]}"; do
    count=$(awk -F '\t' -v c="$cat" '$1==c{n++} END{print n+0}' "$CATEGORIZED_ITEMS")
    if [[ "$count" -eq 0 ]]; then
      continue
    fi
    echo
    echo "## ${cat} (${count}개)"
    awk -F '\t' -v c="$cat" '$1==c{printf "- **%s** | [%s](%s)\n  %s\n\n", $2, $3, $5, $4}' "$CATEGORIZED_ITEMS"
  done
} > "$REPORT_FILE"

TELEGRAM_MESSAGE="$(cat "$TELEGRAM_MESSAGE_FILE")"
send_telegram "$TELEGRAM_MESSAGE" || fail "텔레그램 알림 전송 실패"

if [[ "$DRY_RUN" == "false" ]]; then
  awk -v date="$RUN_DATE" -F '\t' '{print date " " $3}' "$UNIQUE_ITEMS" >> "$SENT_URLS_FILE"
  python3 - "$SENT_URLS_FILE" <<'PYEOF'
import sys
from datetime import datetime, timedelta

path = sys.argv[1]
cutoff = (datetime.now() - timedelta(days=60)).strftime("%Y-%m-%d")

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    lines = [l.strip() for l in f if l.strip()]

lines = [l for l in lines if l.split(' ', 1)[0] >= cutoff]

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n" if lines else "")
PYEOF
fi

if [[ "$DRY_RUN" == "false" ]]; then
  VAULT_DIR="${VAULT_ACCOUNTING:-$HOME/vault/10-knowledge/accounting}"
  mkdir -p "$VAULT_DIR"
  VAULT_FILE="$VAULT_DIR/news-$RUN_DATE.md"
  {
    printf -- "---\ntype: research\ndomain: accounting\nsource: accounting-news\ndate: %s\nstatus: done\n---\n\n" "$RUN_DATE"
    cat "$REPORT_FILE"
  } > "$VAULT_FILE"
  echo "[VAULT] Saved -> $VAULT_FILE"
fi

echo "[DONE] Report: $REPORT_FILE"
echo "[DONE] Total: $TOTAL_COUNT | Categorized: $CATEGORIZED_COUNT"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY-RUN] Telegram message was not sent."
fi
