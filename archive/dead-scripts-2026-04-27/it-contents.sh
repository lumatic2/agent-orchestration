#!/usr/bin/env bash

set -euo pipefail

# Load secrets: GCP Secret Manager → .env fallback
_S="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/secrets_load.sh"
# shellcheck disable=SC1090
[ -f "$_S" ] && source "$_S" 2>/dev/null; unset _S

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
REPORTS_DIR="$BASE_DIR/reports"
TELEGRAM_SCRIPT="$SCRIPTS_DIR/telegram-send.sh"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.5-flash}"

# nvm PATH 보장 (비대화형 SSH에서 .zshrc 미로드 시)
if [[ -d "$HOME/.nvm" ]]; then
  NVM_BIN="$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V | tail -1)"
  [[ -n "$NVM_BIN" && ":$PATH:" != *":$NVM_BIN:"* ]] && export PATH="$NVM_BIN:$PATH"
fi

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
REEXPOSED_ITEMS="$TMP_DIR/reexposed.tsv"
COLLECTED_LIST="$TMP_DIR/collected_list.txt"
SUMMARY_PROMPT="$TMP_DIR/summary_prompt.txt"
IMMEDIATE_ITEMS="$TMP_DIR/immediate.tsv"
LATER_ITEMS="$TMP_DIR/later.tsv"
OVERVIEW_FILE="$TMP_DIR/overview.txt"

NEWSAPI_ITEMS="$TMP_DIR/newsapi_items.tsv"
touch "$RSS_ITEMS" "$WEB_ITEMS" "$ALL_ITEMS" "$UNIQUE_ITEMS" "$REEXPOSED_ITEMS" "$IMMEDIATE_ITEMS" "$LATER_ITEMS" "$OVERVIEW_FILE" "$NEWSAPI_ITEMS"

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
    headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"},
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
  # YouTube 채널: 핸들 → 채널 ID 자동 추출 → RSS 수집
  python3 - "$WEB_ITEMS" <<'PYEOF'
import sys, urllib.request, re
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

out_path = sys.argv[1]
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
cutoff = datetime.now(timezone.utc) - timedelta(hours=72)
rows = []

def fetch(url, timeout=15):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", errors="ignore")

YT_HANDLES = [
    ("조코딩", "jocoding"),
    ("bkamp_ai", "bkamp_ai"),
    ("maker-evan", "maker-evan"),
    ("ddokham", "ddokham"),
]
for source_name, handle in YT_HANDLES:
    try:
        page = fetch(f"https://www.youtube.com/@{handle}", timeout=10)
        m = re.search(r'"(?:channelId|externalId|browseId)":"(UC[^"]+)"', page)
        if not m:
            print(f"[WARN] {source_name}: 채널 ID 못 찾음", file=sys.stderr)
            continue
        rss_url = f"https://www.youtube.com/feeds/videos.xml?channel_id={m.group(1)}"
        feed = fetch(rss_url, timeout=10)
        root = ET.fromstring(feed)
        ns = {"atom": "http://www.w3.org/2005/Atom"}
        count = 0
        for entry in root.findall("atom:entry", ns)[:5]:
            t = entry.find("atom:title", ns)
            l = entry.find("atom:link", ns)
            pub = entry.find("atom:published", ns)
            if t is None or l is None:
                continue
            # YouTube는 7일 이내로 완화 (업로드 주기가 낮음)
            try:
                raw = (pub.text or "").strip()
                if raw.endswith("Z"):
                    raw = raw[:-1] + "+00:00"
                dt = datetime.fromisoformat(raw)
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)
                yt_cutoff = datetime.now(timezone.utc) - timedelta(days=7)
                if dt < yt_cutoff:
                    continue
            except Exception:
                pass
            rows.append((source_name, (t.text or "").strip(), l.get("href", ""), "WEB"))
            count += 1
        print(f"[{source_name}] {count}개", file=sys.stderr)
    except Exception as e:
        print(f"[WARN] {source_name}: {e}", file=sys.stderr)

seen, unique = set(), []
for row in rows:
    if row[2] not in seen:
        seen.add(row[2])
        unique.append(row)

with open(out_path, "w", encoding="utf-8") as f:
    for row in unique:
        f.write("\t".join(row) + "\n")
print(f"[YouTube수집] 총 {len(unique)}개", file=sys.stderr)
PYEOF
}

summarize_items() {
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

  local tmp_prompt="$TMP_DIR/prompt_summary_$$.txt"
  cp "$SUMMARY_PROMPT" "$tmp_prompt"
  local result
  result=$(cd /tmp && gemini --yolo -m "$GEMINI_MODEL" < "$tmp_prompt" 2>&1 | grep -Ev "YOLO mode is enabled|All tool calls will be automatically approved|Loaded cached credentials")
  rm -f "$tmp_prompt"

  if [[ -z "$result" ]]; then
    echo "[WARN] Gemini 응답 없음: 통합 요약" >&2
  fi

  local result_file="$TMP_DIR/summary_result_$$.txt"
  printf '%s\n' "$result" > "$result_file"

  python3 - "$IMMEDIATE_ITEMS" "$LATER_ITEMS" "$result_file" <<'PYEOF'
import sys

immediate_path, later_path, result_file = sys.argv[1], sys.argv[2], sys.argv[3]

immediate = []
later = []

with open(result_file, encoding="utf-8", errors="ignore") as f:
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
  rm -f "$result_file"
}

generate_overview() {
  local overview_prompt="$TMP_DIR/overview_prompt.txt"

  {
    cat <<'PROMPT'
아래는 오늘 수집된 IT 콘텐츠 목록이다. 주제별로 묶어서 오늘의 기술 동향을 정리해줘.

출력 형식 (반드시 이 형식 그대로):

## 🤖 AI/LLM
2-3문장 요약

## 🛠 개발/툴
2-3문장 요약

## 🏢 업계 동향
2-3문장 요약

규칙:
- 해당 주제의 콘텐츠가 없으면 그 섹션은 생략
- 섹션은 최소 2개, 최대 4개 (위 3개 외에 필요하면 🌐 플랫폼/서비스 추가 가능)
- 각 섹션은 2-3문장, 읽히는 글투로
- 딱딱한 보고서 말투 X

목록:
PROMPT
    if [[ -s "$IMMEDIATE_ITEMS" ]]; then
      awk -F '\t' '{ printf "- %s (%s)\n", $2, $1 }' "$IMMEDIATE_ITEMS"
    else
      awk -F '\t' '{ printf "- %s (%s)\n", $2, $1 }' "$UNIQUE_ITEMS" | head -20
    fi
  } > "$overview_prompt"

  local result
  result=$(cd /tmp && gemini --yolo -m "$GEMINI_MODEL" < "$overview_prompt" 2>&1 | grep -Ev "YOLO mode is enabled|All tool calls will be automatically approved|Loaded cached credentials")

  if [[ -z "$result" ]]; then
    echo "[WARN] Gemini 응답 없음: 종합 분석" >&2
    return 0
  fi

  # ## 섹션 구조를 Telegram HTML로 변환
  local result_file="$TMP_DIR/overview_result_$$.txt"
  printf '%s\n' "$result" > "$result_file"

  python3 - "$OVERVIEW_FILE" "$result_file" <<'PYEOF'
import sys, re

out_path = sys.argv[1]
result_file = sys.argv[2]

sections = []
current_header = None
current_body = []

with open(result_file, encoding="utf-8", errors="ignore") as f:
    for raw in f:
        line = raw.rstrip()
        if re.match(r'^\s*#{1,6}\s+', line):
            if current_header is not None:
                body = ' '.join(current_body).strip()
                if body:
                    sections.append((current_header, body))
            current_header = re.sub(r'^\s*#{1,6}\s+', '', line).strip()
            current_body = []
        elif re.match(r'^\s*(---|===|```)', line):
            continue
        else:
            line = re.sub(r'^\s*(?:\d+[.)]\s*|[•\-\*]\s*)', '', line).strip()
            if len(line) > 10:
                current_body.append(line)

if current_header is not None:
    body = ' '.join(current_body).strip()
    if body:
        sections.append((current_header, body))

out_parts = []
for header, body in sections:
    out_parts.append(f"<b>{header}</b>\n{body}")

with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n\n".join(out_parts) + "\n")
PYEOF
  rm -f "$result_file"
}


collect_newsapi_sources() {
  local api_key="${NEWSAPI_KEY:-}"
  if [[ -z "$api_key" ]]; then
    echo "[WARN] NEWSAPI_KEY 미설정 — NewsAPI 수집 건너뜀" >&2
    return 0
  fi
  python3 - "$api_key" "$NEWSAPI_ITEMS" << 'INNEREOF'
import sys, json, urllib.request
from datetime import datetime
api_key, out_path = sys.argv[1], sys.argv[2]
def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent":"Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read())
rows = []
today = datetime.now().strftime("%Y-%m-%d")
try:
    data = fetch(f"https://newsapi.org/v2/top-headlines?category=technology&language=en&pageSize=20&apiKey={api_key}")
    for a in (data.get("articles") or []):
        t = (a.get("title") or "").split(" - ")[0].strip()
        u = a.get("url") or ""
        if t and u and "[Removed]" not in t:
            rows.append(("NewsAPI/기술", t, u, today))
except Exception as e:
    print(f"[WARN] NewsAPI 기술: {e}", file=sys.stderr)
try:
    data = fetch(f"https://newsapi.org/v2/top-headlines?country=kr&pageSize=20&apiKey={api_key}")
    for a in (data.get("articles") or []):
        t = (a.get("title") or "").split(" - ")[0].strip()
        u = a.get("url") or ""
        if t and u and "[Removed]" not in t:
            rows.append(("NewsAPI/일반", t, u, today))
except Exception as e:
    print(f"[WARN] NewsAPI 일반: {e}", file=sys.stderr)
with open(out_path, "w", encoding="utf-8") as f:
    for row in rows: f.write("\t".join(row) + "\n")
print(f"[NewsAPI] {len(rows)}개 수집")
INNEREOF
}

collect_rss_sources() {
  local -a ALL_FEEDS=(
    # 개인 기술 블로그
    "망나니개발자|https://mangkyu.tistory.com/rss"
    "twofootdog|https://twofootdog.tistory.com/rss"
    "bongman|https://bongman.tistory.com/rss"
    "조대협|https://bcho.tistory.com/rss"
    # 뉴스/큐레이션
    "긱뉴스|https://news.hada.io/rss/news"
    "요즘IT|https://yozm.wishket.com/magazine/feed/"
    "pytorch.kr|https://discuss.pytorch.kr/latest.rss"
    "aisparkup|https://aisparkup.com/feed"
    # 기업 테크 블로그
    "SK C&C|https://rss.blog.naver.com/skcc_official.xml"
    "네이버 D2|https://d2.naver.com/d2.atom"
    "우아한형제들|https://techblog.woowahan.com/feed"
    "토스테크|https://toss.tech/rss.xml"
    "카카오테크|https://tech.kakao.com/feed"
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

collect_rss_sources
collect_web_sources
collect_newsapi_sources

cat "$RSS_ITEMS" "$WEB_ITEMS" "$NEWSAPI_ITEMS" > "$ALL_ITEMS"

python3 - "$ALL_ITEMS" "$UNIQUE_ITEMS" "$REEXPOSED_ITEMS" "$SENT_URLS_FILE" <<'PYEOF'
import sys
from datetime import datetime, timedelta

in_path = sys.argv[1]
out_path = sys.argv[2]
reexposed_path = sys.argv[3]
sent_urls_path = sys.argv[4]
today = datetime.now().strftime("%Y-%m-%d")
cutoff = datetime.now() - timedelta(days=7)

# 이미 전송한 URL 로드 ("YYYY-MM-DD URL" 또는 plain URL 형식 모두 지원)
with open(sent_urls_path, "r", encoding="utf-8", errors="ignore") as f:
    sent_urls = {}
    for line in f:
        line = line.strip()
        if not line:
            continue
        parts = line.split(' ', 1)
        if len(parts) == 2 and len(parts[0]) == 10:
            sent_urls[parts[1]] = parts[0]
        else:
            sent_urls[parts[0]] = today

seen = set()
rows = []
reexposed_rows = []

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
        seen.add(key)
        sent_date = sent_urls.get(url)
        if sent_date:
            try:
                sent_dt = datetime.strptime(sent_date, "%Y-%m-%d")
            except ValueError:
                sent_dt = datetime.now()
            if sent_dt >= cutoff:
                display_date = sent_date if not date_text else date_text
                reexposed_rows.append((source, title, url, display_date))
            continue
        rows.append((source, title, url, date_text))

with open(out_path, "w", encoding="utf-8") as out:
    for row in rows:
        out.write("\t".join(row) + "\n")

with open(reexposed_path, "w", encoding="utf-8") as out:
    for row in reexposed_rows:
        out.write("\t".join(row) + "\n")
PYEOF

TOTAL_COUNT=$(wc -l < "$UNIQUE_ITEMS" 2>/dev/null | tr -d ' ')
REEXPOSED_COUNT=$(wc -l < "$REEXPOSED_ITEMS" 2>/dev/null | tr -d ' ')

if [[ "$TOTAL_COUNT" -eq 0 ]]; then
  {
    echo "# IT 콘텐츠 — $RUN_DATE"
    echo
    echo "> 수집: 0개 항목 | 즉시읽기 0개 | 나중에 0개 | 다시보기 ${REEXPOSED_COUNT}개"
    echo
    echo "## 즉시읽기 (0개)"
    echo "- 없음"
    echo
    echo "## 나중에 (0개)"
    echo "- 없음"
    echo
    echo "## 다시 보기 — 최근 7일 (${REEXPOSED_COUNT}개)"
    if [[ "$REEXPOSED_COUNT" -gt 0 ]]; then
      while IFS=$'\t' read -r source title url date_text; do
        [[ -z "${source:-}" ]] && continue
        echo "- **$source** | [$title]($url)${date_text:+ *($date_text)*}"
      done < "$REEXPOSED_ITEMS"
    else
      echo "- 없음"
    fi
  } > "$REPORT_FILE"

  send_telegram "[IT 콘텐츠] $RUN_DATE
오늘 새 항목 없음" || fail "텔레그램 알림 전송 실패"

  echo "[DONE] Report: $REPORT_FILE"
  echo "[DONE] No new items."
  exit 0
fi

awk -F '\t' '{ printf "%s | %s | %s\n", $1, $2, $3 }' "$UNIQUE_ITEMS" > "$COLLECTED_LIST"

summarize_items
generate_overview

IMMEDIATE_COUNT=$(wc -l < "$IMMEDIATE_ITEMS" 2>/dev/null | tr -d ' ')
LATER_COUNT=$(wc -l < "$LATER_ITEMS" 2>/dev/null | tr -d ' ')

if [[ "$IMMEDIATE_COUNT" -eq 0 && "$LATER_COUNT" -eq 0 ]]; then
  fail "Gemini 요약 결과 파싱 실패"
fi

{
  echo "# IT 콘텐츠 — $RUN_DATE"
  echo
  echo "> 수집: ${TOTAL_COUNT}개 항목 | 즉시읽기 ${IMMEDIATE_COUNT}개 | 나중에 ${LATER_COUNT}개 | 다시보기 ${REEXPOSED_COUNT}개"
  echo
  if [[ -s "$OVERVIEW_FILE" ]]; then
    echo "## 오늘의 동향"
    cat "$OVERVIEW_FILE"
    echo
  fi
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
  echo
  echo "## 다시 보기 — 최근 7일 (${REEXPOSED_COUNT}개)"
  if [[ "$REEXPOSED_COUNT" -gt 0 ]]; then
    while IFS=$'\t' read -r source title url date_text; do
      [[ -z "${source:-}" ]] && continue
      echo "- **$source** | [$title]($url)${date_text:+ *($date_text)*}"
    done < "$REEXPOSED_ITEMS"
  else
    echo "- 없음"
  fi
} > "$REPORT_FILE"

TELEGRAM_PREVIEW="$TMP_DIR/telegram_preview.txt"
if [[ "$IMMEDIATE_COUNT" -gt 0 ]]; then
  head -n 3 "$IMMEDIATE_ITEMS" | while IFS=$'\t' read -r source title summary url; do
    [[ -z "${source:-}" ]] && continue
    if [[ -n "${url:-}" ]]; then
      echo "• <b>$source</b> | <a href=\"$url\">$title</a>"
    else
      echo "• <b>$source</b> | $title"
    fi
    if [[ -n "${summary:-}" ]]; then
      echo "  $summary"
    fi
    echo ""
  done > "$TELEGRAM_PREVIEW"
else
  echo "• 즉시읽기 항목 없음" > "$TELEGRAM_PREVIEW"
fi

OVERVIEW_TEXT=""
if [[ -s "$OVERVIEW_FILE" ]]; then
  OVERVIEW_TEXT="$(cat "$OVERVIEW_FILE")"
fi

TELEGRAM_MESSAGE="[IT 콘텐츠] $RUN_DATE
즉시읽기 ${IMMEDIATE_COUNT}개 | 나중에 ${LATER_COUNT}개 | 다시보기 ${REEXPOSED_COUNT}개

<b>📊 오늘의 동향</b>
${OVERVIEW_TEXT}
<b>📌 즉시읽기 TOP 3</b>
$(cat "$TELEGRAM_PREVIEW")
💬 AI 분석: 이 봇에 <code>/it-contents</code> 전송"

send_telegram "$TELEGRAM_MESSAGE" || fail "텔레그램 알림 전송 실패"

# 전송 완료된 URL 기록 (dry-run 제외)
if [[ "$DRY_RUN" == "false" ]]; then
  awk -v date="$RUN_DATE" -F '\t' '{print date " " $3}' "$UNIQUE_ITEMS" >> "$SENT_URLS_FILE"
  # 30일치만 유지 (날짜 기준 정리)
  python3 - "$SENT_URLS_FILE" <<'PYEOF'
import sys
from datetime import datetime, timedelta
path = sys.argv[1]
cutoff = (datetime.now() - timedelta(days=30)).strftime("%Y-%m-%d")
with open(path) as f:
    lines = [l.strip() for l in f if l.strip()]
lines = [l for l in lines if l.split(' ', 1)[0] >= cutoff]
with open(path, "w") as f:
    f.write("\n".join(lines) + "\n" if lines else "")
PYEOF
fi

# vault 저장
if [[ "$DRY_RUN" == "false" ]]; then
  VAULT_DIR="${VAULT_RESEARCH:-$HOME/vault/10-knowledge/research}"
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
