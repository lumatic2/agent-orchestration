#!/usr/bin/env bash

set -euo pipefail

# Load secrets: GCP Secret Manager → .env fallback
_S="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/secrets_load.sh"
# shellcheck disable=SC1090
[ -f "$_S" ] && source "$_S" 2>/dev/null; unset _S

DRY_RUN=false

usage() {
  echo "Usage: bash events-tracker.sh [--dry-run]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# 행사·공모전 전용 채팅방 우선 사용
if [[ -n "${TELEGRAM_BOT_TOKEN_IT:-}" ]]; then
  export TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN_IT"
fi
if [[ -n "${TELEGRAM_CHAT_ID_EVENTS:-}" ]]; then
  export TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID_EVENTS"
fi

BASE_DIR="$HOME/projects/agent-orchestration"
SCRIPTS_DIR="$BASE_DIR/scripts"
LOGS_DIR="$BASE_DIR/logs"
REPORTS_DIR="$BASE_DIR/reports"
TELEGRAM_SCRIPT="$SCRIPTS_DIR/telegram-send.sh"
SLACK_SCRIPT="$SCRIPTS_DIR/slack-send.sh"
ORCH_SCRIPT="$SCRIPTS_DIR/orchestrate.sh"

mkdir -p "$REPORTS_DIR" "$LOGS_DIR"

send_telegram() {
  local msg="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    bash "$TELEGRAM_SCRIPT" --dry-run --message "$msg"
  else
    bash "$TELEGRAM_SCRIPT" --message "$msg"
  fi
}

send_slack() {
  local msg="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    bash "$SLACK_SCRIPT" --dry-run --message "$msg"
  else
    bash "$SLACK_SCRIPT" --message "$msg"
  fi
}

fail() {
  local msg="$1"
  echo "[ERROR] $msg" >&2
  send_telegram "[행사·공모전] 수집 실패: $msg" || true
  exit 1
}

[[ -x "$ORCH_SCRIPT" ]]   || fail "orchestrate.sh를 찾을 수 없습니다"
[[ -x "$TELEGRAM_SCRIPT" ]] || fail "telegram-send.sh를 찾을 수 없습니다"
[[ -x "$SLACK_SCRIPT" ]]   || fail "slack-send.sh를 찾을 수 없습니다"

run_orchestrate() {
  local prompt="$1"
  local task_name="$2"
  local timeout_sec="${3:-300}"

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

RUN_DATE="$(date +%Y-%m-%d)"
WEEK_NUM="$(date +%Y-W%V)"
SLUG="$(date +%Y%m%d_%H%M%S)"
REPORT_FILE="$REPORTS_DIR/events-tracker-$RUN_DATE.md"
LOCK_FILE="$LOGS_DIR/.events-tracker-$WEEK_NUM.lock"

if [[ -f "$LOCK_FILE" && "$DRY_RUN" == "false" ]]; then
  echo "[SKIP] 이번 주($WEEK_NUM) 이미 실행됨"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

COLLECT_LOG_NAME="events-collect-$SLUG"
CLASSIFY_LOG_NAME="events-classify-$SLUG"
PERSONAL_FILE="$TMP_DIR/personal.txt"
COMPANY_FILE="$TMP_DIR/company.txt"
OVERVIEW_FILE="$TMP_DIR/overview.txt"
touch "$PERSONAL_FILE" "$COMPANY_FILE" "$OVERVIEW_FILE"

echo "[1/3] 행사 수집 중... (Gemini → K-Startup, IITP, NIA, AI Hub, NIPA, 과기정통부, 중기부, 긱뉴스 외)"
# --- 1단계: Gemini로 행사 수집 ---
COLLECT_PROMPT="다음 두 기준 중 하나라도 해당하는 공모전·경진대회·해커톤·창업지원사업을 수집해줘.

[수집 기준]
1. 최근 30일 이내 신규 공고된 행사
2. 공고 시점과 관계없이 현재 참가신청을 받고 있는 행사 (접수 중 또는 접수 예정 포함)

[수집 소스]
- K-Startup 창업지원포털: https://www.k-startup.go.kr
- IITP 공고: https://www.iitp.kr
- NIA 공고: https://www.nia.or.kr
- AI Hub 공모전: https://www.aihub.or.kr
- NIPA 공고: https://www.nipa.kr
- 과기정통부 보도자료: https://www.msit.go.kr
- 중기부 공고: https://www.mss.go.kr
- 긱뉴스: https://news.hada.io
- Dacon AI 경진대회: https://dacon.io/competitions
- Kaggle 대회: https://www.kaggle.com/competitions
- 전국민AI경진대회 등 대형 AI 챌린지도 웹 검색으로 추가 확인

[출력 형식 — 반드시 준수]
주관기관 | 행사명 | 마감일 | URL
마감일 모를 경우 '미정'으로 표기. 한 줄에 하나씩."

NO_VAULT=true run_orchestrate "$COLLECT_PROMPT" "$COLLECT_LOG_NAME" 300 || true

COLLECT_LOG="$(latest_gemini_log "$COLLECT_LOG_NAME")"
[[ -n "$COLLECT_LOG" ]] || fail "수집 로그를 찾을 수 없습니다"

ITEM_LIST="$TMP_DIR/item_list.txt"
grep -E '^\s*[-*]?\s*.+\s*\|.+\|.+\|.+' "$COLLECT_LOG" | \
  sed 's/^[[:space:]]*[-*][[:space:]]*//' > "$ITEM_LIST" || true

TOTAL_COUNT=$(wc -l < "$ITEM_LIST" 2>/dev/null | tr -d ' ')
echo "[1/3] 수집 완료 — ${TOTAL_COUNT}개 항목"

if [[ "$TOTAL_COUNT" -eq 0 ]]; then
  {
    echo "# 행사·공모전 — $RUN_DATE"
    echo "> 수집: 0개"
  } > "$REPORT_FILE"
  send_telegram "[행사·공모전] $RUN_DATE — 수집된 항목 없음" || true
  [[ "$DRY_RUN" == "false" ]] && touch "$LOCK_FILE"
  echo "[DONE] No events found."
  exit 0
fi

echo "[2/3] 개인/회사 분류 중... (Gemini)"
# --- 2단계: Gemini로 개인/회사 분류 ---
CLASSIFY_PROMPT="아래 행사·공모전 목록을 분류하고, 각 섹션 내에서 우선순위 순으로 정렬해줘.

분류 기준:
- 개인참여: 개인 자격으로 참가 가능한 행사. 예) AI·개발 경진대회, 해커톤, 아이디어 공모전, 논문·포스터 발표, 챌린지
- 회사참여: 법인·스타트업 자격이 필요한 행사. 예) 정부 지원사업, 창업패키지, 바우처, R&D 과제, 액셀러레이팅, IR 프로그램, 수출 지원
- 스킵: 위 두 분류와 무관한 것 (음악·미술·체육 등)

우선순위 정렬 기준 (높은 순):
1. AI·개발·데이터 관련도 높을수록
2. 마감일이 임박할수록 (미정은 하위)
3. 규모·인지도 높을수록 (전국 단위 > 지역)

설명은 2줄로 작성:
- 1줄: 행사 성격과 주제 요약
- 2줄: 지원 자격 또는 혜택 핵심 (상금, 지원금, 네트워킹 등)

출력 형식(반드시 준수):
## 개인참여
- 주관기관 | 행사명 | 마감일 | 설명1줄 | 설명2줄 | URL

## 회사참여
- 주관기관 | 행사명 | 마감일 | 설명1줄 | 설명2줄 | URL

## 스킵
- 행사명

목록:
$(cat "$ITEM_LIST")"

NO_VAULT=true run_orchestrate "$CLASSIFY_PROMPT" "$CLASSIFY_LOG_NAME" 300 || true

CLASSIFY_LOG="$(latest_gemini_log "$CLASSIFY_LOG_NAME")"
[[ -n "$CLASSIFY_LOG" ]] || fail "분류 로그를 찾을 수 없습니다"

awk -v p="$PERSONAL_FILE" -v c="$COMPANY_FILE" '
BEGIN { section="" }
/^##[[:space:]]*개인참여/ { section="p"; next }
/^##[[:space:]]*회사참여/ { section="c"; next }
/^##[[:space:]]*스킵/     { section="s"; next }
section=="p" && /^[-*] / { sub(/^[-*] /, ""); print >> p; next }
section=="c" && /^[-*] / { sub(/^[-*] /, ""); print >> c; next }
' "$CLASSIFY_LOG"

PERSONAL_COUNT=$(wc -l < "$PERSONAL_FILE" 2>/dev/null | tr -d ' ')
COMPANY_COUNT=$(wc -l < "$COMPANY_FILE" 2>/dev/null | tr -d ' ')
echo "[2/3] 분류 완료 — 개인참여 ${PERSONAL_COUNT}개 / 회사참여 ${COMPANY_COUNT}개"

# 종합 분석 생성
OVERVIEW_TASK="events-overview-$SLUG"
OVERVIEW_PROMPT="$TMP_DIR/overview_prompt.txt"
{
  cat <<'PROMPT'
아래는 이번 주 수집된 공모전·행사·지원사업 목록이다. 분야별로 묶어서 이번 주 기회를 정리해줘.

출력 형식 (반드시 이 형식 그대로):

## 🚀 창업/스타트업
2-3문장 요약

## 🧑‍💻 AI/개발
2-3문장 요약

## ⏰ 마감 임박
마감이 가까운 항목 1-2개 언급

규칙:
- 해당 분야의 항목이 없으면 그 섹션은 생략
- 섹션은 최소 2개, 최대 4개 (위 3개 외에 필요하면 🎓 학술/교육 추가 가능)
- 각 섹션은 2-3문장, 읽히는 글투로
- 딱딱한 공문서 말투 X

개인참여 항목:
PROMPT
  if [[ -s "$PERSONAL_FILE" ]]; then
    awk -F'|' '{printf "- %s | %s | 마감: %s\n", $2, $4, $3}' "$PERSONAL_FILE" | head -15
  fi
} > "$OVERVIEW_PROMPT"

OVERVIEW_RUN_OK=true
NO_VAULT=true run_orchestrate "$(cat "$OVERVIEW_PROMPT")" "$OVERVIEW_TASK" 180 || OVERVIEW_RUN_OK=false

OVERVIEW_LOG="$(latest_gemini_log "$OVERVIEW_TASK")"
if [[ -n "$OVERVIEW_LOG" ]]; then
  python3 - "$OVERVIEW_LOG" "$OVERVIEW_FILE" <<'PYEOF'
import sys, re
log_path, out_path = sys.argv[1], sys.argv[2]

sections = []
current_header = None
current_body = []

with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
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
  [[ "$OVERVIEW_RUN_OK" != "true" ]] && echo "[WARN] Gemini overview 호출 종료 지연. 생성된 로그 사용." >&2
else
  echo "[WARN] Gemini overview 로그 없음, 스킵" >&2
fi

echo "[3/3] 리포트 생성 및 발송 중..."

# 리포트 출력 헬퍼
print_section() {
  local file="$1"
  if [[ -s "$file" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      IFS='|' read -r org name deadline desc1 desc2 url <<< "$line"
      org="$(echo "${org:-}" | xargs)"; name="$(echo "${name:-}" | xargs)"
      deadline="$(echo "${deadline:-}" | xargs)"
      desc1="$(echo "${desc1:-}" | xargs)"; desc2="$(echo "${desc2:-}" | xargs)"
      url="$(echo "${url:-}" | xargs)"
      echo "- **$org** | $name | ~$deadline"
      [[ -n "$desc1" ]] && echo "  $desc1"
      [[ -n "$desc2" ]] && echo "  $desc2"
      [[ -n "$url" ]]   && echo "  $url"
      echo
    done < "$file"
  else
    echo "- 없음"; echo
  fi
}

# --- 리포트 생성 ---
{
  echo "# 행사·공모전 — $RUN_DATE"
  echo
  echo "> 수집: ${TOTAL_COUNT}개 | 개인참여 ${PERSONAL_COUNT}개 | 회사참여 ${COMPANY_COUNT}개"
  echo
  if [[ -s "$OVERVIEW_FILE" ]]; then
    echo "## 이번 주 동향"
    cat "$OVERVIEW_FILE"
    echo
  fi
  echo "## 👤 개인참여 (${PERSONAL_COUNT}개)"
  print_section "$PERSONAL_FILE"
  echo "## 🏢 회사참여 (${COMPANY_COUNT}개)"
  print_section "$COMPANY_FILE"
} > "$REPORT_FILE"

# 미리보기 생성 헬퍼 (상위 5개, 설명 2줄 + 링크)
make_preview() {
  local file="$1"
  if [[ -s "$file" ]]; then
    head -n 3 "$file" | while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      IFS='|' read -r org name deadline desc1 desc2 url <<< "$line"
      org="$(echo "${org:-}" | xargs)"; name="$(echo "${name:-}" | xargs)"
      deadline="$(echo "${deadline:-}" | xargs)"
      desc1="$(echo "${desc1:-}" | xargs)"; desc2="$(echo "${desc2:-}" | xargs)"
      url="$(echo "${url:-}" | xargs)"
      if [[ -n "$url" ]]; then
        echo "• <a href=\"$url\">$name</a> (~$deadline)"
      else
        echo "• $name (~$deadline)"
      fi
      [[ -n "$desc1" ]] && echo "  $desc1"
      [[ -n "$desc2" ]] && echo "  $desc2"
      echo ""
    done
  else
    echo "• 해당 항목 없음"
  fi
}

PERSONAL_PREVIEW="$TMP_DIR/personal_preview.txt"
COMPANY_PREVIEW="$TMP_DIR/company_preview.txt"
make_preview "$PERSONAL_FILE" "$PERSONAL_COUNT" > "$PERSONAL_PREVIEW"
make_preview "$COMPANY_FILE"  "$COMPANY_COUNT"  > "$COMPANY_PREVIEW"

OVERVIEW_TEXT=""
[[ -s "$OVERVIEW_FILE" ]] && OVERVIEW_TEXT="$(cat "$OVERVIEW_FILE")"

# --- 텔레그램: 개인참여 ---
send_telegram "[행사·공모전] $RUN_DATE — 개인참여 ${PERSONAL_COUNT}개

<b>📊 이번 주 동향</b>
${OVERVIEW_TEXT}
<b>📌 개인참여 TOP 3</b>
$(cat "$PERSONAL_PREVIEW")
💬 AI 분석: 이 봇에 <code>/events</code> 전송" || fail "텔레그램 발송 실패"

# --- Slack: 회사참여 ---
send_slack "[행사·공모전] $RUN_DATE — 회사참여 ${COMPANY_COUNT}개

$(cat "$COMPANY_PREVIEW")" || fail "Slack 발송 실패"

[[ "$DRY_RUN" == "false" ]] && touch "$LOCK_FILE"

# vault 저장
if [[ "$DRY_RUN" == "false" ]]; then
  VAULT_DIR="$HOME/vault/10-knowledge/research"
  mkdir -p "$VAULT_DIR"
  VAULT_FILE="$VAULT_DIR/events-tracker-$RUN_DATE.md"
  {
    printf -- "---\ntype: research\ndomain: events\nsource: events-tracker\ndate: %s\nstatus: done\n---\n\n" "$RUN_DATE"
    cat "$REPORT_FILE"
  } > "$VAULT_FILE"
  echo "[VAULT] Saved → $VAULT_FILE"
fi

echo "[DONE] Report: $REPORT_FILE"
echo "[DONE] Personal: $PERSONAL_COUNT | Company: $COMPANY_COUNT | Total: $TOTAL_COUNT"
if [[ "$DRY_RUN" == "true" ]]; then echo "[DRY-RUN] Messages were not sent."; fi
