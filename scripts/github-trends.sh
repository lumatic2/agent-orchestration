#!/usr/bin/env bash

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Load secrets: GCP Secret Manager → .env fallback
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
[ -f "$SCRIPT_DIR/env.sh" ] && source "$SCRIPT_DIR/env.sh"
_S="$SCRIPT_DIR/secrets_load.sh"
# shellcheck disable=SC1090
[ -f "$_S" ] && source "$_S" 2>/dev/null; unset _S

DRY_RUN=false

usage() {
  echo "Usage: bash github-trends.sh [--dry-run]"
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

# GitHub 트렌드 전용 채팅방 우선 사용
if [[ -n "${TELEGRAM_BOT_TOKEN_IT:-}" ]]; then
  export TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN_IT"
fi
if [[ -n "${TELEGRAM_CHAT_ID_GITHUB:-}" ]]; then
  export TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID_GITHUB"
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

date_7_days_ago() {
  if date -v-7d +%Y-%m-%d >/dev/null 2>&1; then
    date -v-7d +%Y-%m-%d
  else
    date -d '7 days ago' +%Y-%m-%d
  fi
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
  send_telegram "[GitHub 트렌드] 수집 실패: $msg" || true
  exit 1
}

command -v gh >/dev/null 2>&1 || fail "gh CLI가 설치되어 있지 않습니다"
[[ -x "$ORCH_SCRIPT" ]] || fail "orchestrate.sh를 찾을 수 없습니다: $ORCH_SCRIPT"
[[ -x "$TELEGRAM_SCRIPT" ]] || fail "telegram-send.sh를 찾을 수 없습니다: $TELEGRAM_SCRIPT"

RUN_DATE="$(date +%Y-%m-%d)"
START_DATE="$(date_7_days_ago)"
SLUG="$(date +%Y%m%d)"
TASK_NAME="github-trends-classify-$SLUG"
REPORT_FILE="$REPORTS_DIR/github-trends-$RUN_DATE.md"
LOCK_FILE="$LOGS_DIR/.github-trends-$RUN_DATE.lock"

if [[ -f "$LOCK_FILE" && "$DRY_RUN" == "false" ]]; then
  echo "[SKIP] 오늘($RUN_DATE) 이미 실행됨 — 중복 실행 방지"
  exit 0
fi
if [[ "$DRY_RUN" == "false" ]]; then
  touch "$LOCK_FILE"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO_TSV="$TMP_DIR/repos.tsv"
PROMPT_FILE="$TMP_DIR/prompt.txt"
IMMEDIATE_FILE="$TMP_DIR/immediate.txt"
REFERENCE_FILE="$TMP_DIR/reference.txt"
SKIP_FILE="$TMP_DIR/skip.txt"
SKIP_REPOS_FILE="$TMP_DIR/skip_repos.txt"
OVERVIEW_FILE="$TMP_DIR/overview.txt"
touch "$OVERVIEW_FILE"

QUERY="search/repositories?q=created:>$START_DATE&sort=stars&order=desc&per_page=50"

gh api "$QUERY" \
  --jq '.items[] | [.full_name, (.stargazers_count|tostring), (.language // "N/A"), (.description // ""), .html_url] | @tsv' \
  > "$REPO_TSV" || fail "GitHub API 호출 실패"

if [[ ! -s "$REPO_TSV" ]]; then
  fail "수집된 레포가 없습니다"
fi

REPO_LIST="$TMP_DIR/repo_list.txt"
awk -F '\t' '{
  desc=$4
  gsub(/[[:cntrl:]]/, " ", desc)
  if (length(desc) > 180) {
    desc=substr(desc,1,177) "..."
  }
  printf("- %s | ★%s | %s | %s | %s\n", $1, $2, $3, desc, $5)
}' "$REPO_TSV" > "$REPO_LIST"

{
  cat <<'PROMPT_HEAD'
아래 GitHub 레포 목록을 분류해줘. 각 항목을 [즉시적용], [참고], [스킵] 중 하나로 분류하고,
즉시적용·참고 항목에는 한 줄 이유와 적용 포인트를 추가해줘.

분류 기준:
- 즉시적용: AI 에이전트, LLM 오케스트레이션, MCP, CLI 자동화, 워크플로우 도구
- 참고: AI/개발 관련이지만 즉시 적용 어려운 것
- 스킵: 무관

출력 형식(반드시 준수):
## 즉시적용
- owner/repo | ★N | 한 줄 이유 | 적용 포인트: ...

## 참고
- owner/repo | ★N | 한 줄 이유

## 스킵
- owner/repo

레포 목록:
PROMPT_HEAD
  cat "$REPO_LIST"
} > "$PROMPT_FILE"

PROMPT_CONTENT="$(cat "$PROMPT_FILE")"

NO_VAULT=true bash "$ORCH_SCRIPT" gemini "$PROMPT_CONTENT" "$TASK_NAME" >/dev/null 2>&1 \
  || fail "Gemini 분류 호출 실패"

CLASSIFY_LOG="$(ls -t "$LOGS_DIR"/gemini_"$TASK_NAME"_*.txt 2>/dev/null | head -1 || true)"
[[ -n "$CLASSIFY_LOG" ]] || fail "Gemini 분류 로그를 찾을 수 없습니다"

awk -v i="$IMMEDIATE_FILE" -v r="$REFERENCE_FILE" -v s="$SKIP_FILE" '
BEGIN { section="" }
/^##[[:space:]]*즉시적용/ { section="i"; next }
/^##[[:space:]]*참고/ { section="r"; next }
/^##[[:space:]]*스킵/ { section="s"; next }
section=="i" && /^- / { print $0 >> i; next }
section=="r" && /^- / { print $0 >> r; next }
section=="s" && /^- / { print $0 >> s; next }
' "$CLASSIFY_LOG"

IMMEDIATE_COUNT=$(wc -l < "$IMMEDIATE_FILE" 2>/dev/null | tr -d ' ')
REFERENCE_COUNT=$(wc -l < "$REFERENCE_FILE" 2>/dev/null | tr -d ' ')
SKIP_COUNT=$(wc -l < "$SKIP_FILE" 2>/dev/null | tr -d ' ')

# 종합 분석 생성
OVERVIEW_SLUG="$(date +%Y%m%d_%H%M%S)"
OVERVIEW_TASK="github-trends-overview-$OVERVIEW_SLUG"
OVERVIEW_PROMPT="$TMP_DIR/overview_prompt.txt"

{
  cat <<'PROMPT'
아래는 이번 주 GitHub에서 가장 빠르게 스타를 받은 레포 목록이다.
이 목록을 바탕으로, 개발 생태계 전문 큐레이터의 시각에서 이번 주 오픈소스 트렌드를 하나의 짧은 칼럼 형식으로 써줘.

조건:
- 번호나 불릿 없이, 자연스럽게 이어지는 문단 형태
- 총 10문장 내외
- 이번 주 두드러진 기술 카테고리, AI·오픈소스 생태계 흐름, 주목할 레포/도구를 녹여서
- 마지막 문장은 이번 주 전체를 아우르는 한 줄 결론으로 마무리
- 딱딱한 보고서 말투 X, 읽히는 글투로

즉시적용 레포:
PROMPT
  if [[ -s "$IMMEDIATE_FILE" ]]; then
    cat "$IMMEDIATE_FILE"
  fi
  echo
  echo "참고 레포 (상위 10개):"
  head -n 10 "$REFERENCE_FILE" 2>/dev/null || true
} > "$OVERVIEW_PROMPT"

OVERVIEW_RUN_OK=true
NO_VAULT=true bash "$ORCH_SCRIPT" gemini "$(cat "$OVERVIEW_PROMPT")" "$OVERVIEW_TASK" >/dev/null 2>&1 \
  || OVERVIEW_RUN_OK=false

OVERVIEW_LOG="$(ls -t "$LOGS_DIR"/gemini_"$OVERVIEW_TASK"_*.txt 2>/dev/null | head -1 || true)"

if [[ -n "$OVERVIEW_LOG" ]]; then
  python3 - "$OVERVIEW_LOG" "$OVERVIEW_FILE" <<'PYEOF'
import sys, re

log_path, out_path = sys.argv[1], sys.argv[2]
lines = []
with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
    for raw in f:
        line = raw.rstrip()
        if re.match(r'^\s*(#{1,6}\s|---|===|```)', line):
            continue
        if re.search(r'(Registering|notification handler|MCP context|Scheduling MCP|Executing MCP|listChanged|capability|Listening anyway|Server .* has tools|Capabilities:', line):
            continue
        line = re.sub(r'^\s*(?:\d+[.)]\s*|[•\-\*]\s*)', '', line).strip()
        if len(line) > 15:
            lines.append(line)

text = ' '.join(lines).strip()
text = re.sub(r'\s{2,}', ' ', text)
with open(out_path, "w", encoding="utf-8") as f:
    f.write(text + "\n")
PYEOF
  [[ "$OVERVIEW_RUN_OK" != "true" ]] && echo "[WARN] Gemini overview 호출 종료 지연. 생성된 로그 사용." >&2
else
  echo "[WARN] Gemini overview 로그 없음, 스킵" >&2
fi

if [[ "$IMMEDIATE_COUNT" -eq 0 && "$REFERENCE_COUNT" -eq 0 && "$SKIP_COUNT" -eq 0 ]]; then
  fail "Gemini 분류 결과 파싱 실패"
fi

if [[ -s "$SKIP_FILE" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    line="${line#- }"
    repo="${line%%|*}"
    repo="$(trim "${repo:-}")"
    if [[ -n "$repo" ]]; then
      echo "$repo"
    fi
  done < "$SKIP_FILE" > "$SKIP_REPOS_FILE"
fi

{
  echo "# GitHub Trends — $RUN_DATE"
  echo
  echo "> 수집 기간: $START_DATE ~ $RUN_DATE | 즉시적용 ${IMMEDIATE_COUNT}개 | 참고 ${REFERENCE_COUNT}개"
  echo
  if [[ -s "$OVERVIEW_FILE" ]]; then
    echo "## 이번 주 동향"
    cat "$OVERVIEW_FILE"
    echo
  fi
  echo "## 즉시적용 (${IMMEDIATE_COUNT}개)"
  if [[ "$IMMEDIATE_COUNT" -gt 0 ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      line="${line#- }"
      IFS='|' read -r repo stars reason point <<< "$line"
      repo="$(trim "${repo:-}")"
      stars="$(trim "${stars:-}")"
      reason="$(trim "${reason:-}")"
      point="$(trim "${point:-}")"
      if [[ "$point" == 적용\ 포인트:* ]]; then
        point="${point#적용 포인트: }"
      fi
      echo "- **$repo** ${stars} this week"
      echo "  $reason"
      if [[ -n "$point" ]]; then
        echo "  → 적용 포인트: $point"
      else
        echo "  → 적용 포인트: 미기재"
      fi
      echo
    done < "$IMMEDIATE_FILE"
  else
    echo "- 없음"
    echo
  fi

  echo "## 참고 (${REFERENCE_COUNT}개)"
  if [[ "$REFERENCE_COUNT" -gt 0 ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      line="${line#- }"
      IFS='|' read -r repo stars reason _ <<< "$line"
      repo="$(trim "${repo:-}")"
      stars="$(trim "${stars:-}")"
      reason="$(trim "${reason:-}")"
      echo "- **$repo** $stars"
      echo "  $reason"
      echo
    done < "$REFERENCE_FILE"
  else
    echo "- 없음"
    echo
  fi

  echo "## 스킵"
  if [[ -s "$SKIP_REPOS_FILE" ]]; then
    awk 'NR==1{printf "%s",$0; next} {printf ", %s",$0} END{printf "\n"}' "$SKIP_REPOS_FILE"
  else
    echo "없음"
  fi
} > "$REPORT_FILE"

TELEGRAM_ITEMS="$TMP_DIR/telegram_items.txt"

head -n 5 "$IMMEDIATE_FILE" 2>/dev/null | while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  line="${line#- }"
  IFS='|' read -r repo stars reason point <<< "$line"
  repo="$(trim "${repo:-}")"
  stars="$(trim "${stars:-}")"
  reason="$(trim "${reason:-}")"
  url="https://github.com/$repo"
  echo "• <a href=\"$url\">$repo</a> $stars"
  [[ -n "$reason" ]] && echo "  $reason"
  echo ""
done > "$TELEGRAM_ITEMS"

if [[ ! -s "$TELEGRAM_ITEMS" ]]; then
  echo "• 즉시적용 항목 없음" > "$TELEGRAM_ITEMS"
fi

OVERVIEW_TEXT=""
[[ -s "$OVERVIEW_FILE" ]] && OVERVIEW_TEXT="$(cat "$OVERVIEW_FILE")"

TELEGRAM_MESSAGE="[GitHub 트렌드] $RUN_DATE
즉시적용 ${IMMEDIATE_COUNT}개 | 참고 ${REFERENCE_COUNT}개

<b>📊 이번 주 동향</b>
${OVERVIEW_TEXT}
<b>📌 즉시적용 TOP 5</b>
$(cat "$TELEGRAM_ITEMS")
💬 AI 분석: 이 봇에 <code>/github-trends</code> 전송"

send_telegram "$TELEGRAM_MESSAGE" || fail "텔레그램 알림 전송 실패"

# vault 저장
if [[ "$DRY_RUN" == "false" ]]; then
  VAULT_DIR="${VAULT_RESEARCH:-$HOME/vault/10-knowledge/research}"
  mkdir -p "$VAULT_DIR"
  VAULT_FILE="$VAULT_DIR/github-trends-$RUN_DATE.md"
  {
    printf -- "---\ntype: research\ndomain: github\nsource: github-trends\ndate: %s\nstatus: done\n---\n\n" "$RUN_DATE"
    cat "$REPORT_FILE"
  } > "$VAULT_FILE"
  echo "[VAULT] Saved → $VAULT_FILE"
fi

echo "[DONE] Report: $REPORT_FILE"
echo "[DONE] Immediate: $IMMEDIATE_COUNT | Reference: $REFERENCE_COUNT | Skip: $SKIP_COUNT"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY-RUN] Telegram message was not sent."
fi
