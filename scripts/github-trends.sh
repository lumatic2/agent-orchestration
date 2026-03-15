#!/usr/bin/env bash

set -euo pipefail

# Load secrets: GCP Secret Manager → .env fallback
_S="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/secrets_load.sh"
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

bash "$ORCH_SCRIPT" gemini "$PROMPT_CONTENT" "$TASK_NAME" >/dev/null 2>&1 \
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
APPLY_CMDS="$TMP_DIR/apply_cmds.txt"

head -n 3 "$IMMEDIATE_FILE" 2>/dev/null | while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  line="${line#- }"
  IFS='|' read -r repo stars reason point <<< "$line"
  repo="$(trim "${repo:-}")"
  reason="$(trim "${reason:-}")"
  echo "• $repo — $reason"
done > "$TELEGRAM_ITEMS"


if [[ ! -s "$TELEGRAM_ITEMS" ]]; then
  echo "• 즉시적용 항목 없음" > "$TELEGRAM_ITEMS"
fi


TELEGRAM_MESSAGE="[GitHub 트렌드] $RUN_DATE
즉시적용 ${IMMEDIATE_COUNT}개 | 참고 ${REFERENCE_COUNT}개

$(cat "$TELEGRAM_ITEMS")
📄 reports/github-trends-$RUN_DATE.md"

send_telegram "$TELEGRAM_MESSAGE" || fail "텔레그램 알림 전송 실패"

# vault 저장
if [[ "$DRY_RUN" == "false" ]]; then
  VAULT_DIR="$HOME/vault/10-knowledge/research"
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
