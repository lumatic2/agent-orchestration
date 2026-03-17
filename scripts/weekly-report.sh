#!/usr/bin/env bash
# ============================================================
# weekly-report.sh — COO 에이전트: 주간 운영 리포트 자동 생성
#
# 사용법:
#   bash weekly-report.sh            # 이번 주 리포트 생성 + Telegram 전송
#   bash weekly-report.sh --dry-run  # 전송 없이 출력만
#   bash weekly-report.sh --days 14  # 지난 14일 기준
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Load env + secrets
[ -f "$SCRIPT_DIR/env.sh" ] && source "$SCRIPT_DIR/env.sh" 2>/dev/null
[ -f "$SCRIPT_DIR/secrets_load.sh" ] && source "$SCRIPT_DIR/secrets_load.sh" 2>/dev/null

# ── 옵션 파싱 ──────────────────────────────────────────────
DRY_RUN=false
DAYS=7

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --days) DAYS="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# ── 날짜 계산 ──────────────────────────────────────────────
TODAY=$(date +%Y-%m-%d)
WEEK_START=$(date -v "-${DAYS}d" +%Y-%m-%d 2>/dev/null || date -d "-${DAYS} days" +%Y-%m-%d)
WEEK_LABEL="${WEEK_START} ~ ${TODAY}"

# ── SCHEDULE.md 파싱 ───────────────────────────────────────
SCHEDULE="$REPO_DIR/SCHEDULE.md"

completed_items=""
inprogress_items=""

if [ -f "$SCHEDULE" ]; then
  # 완료 항목 [x]
  completed_items=$(grep -E '^\- \[x\]' "$SCHEDULE" \
    | sed 's/^- \[x\] \[.*\] //' \
    | sed 's/ `[^`]*`//g' \
    | sed 's/ #[^ ]*//' \
    | head -10)

  # 진행 중 항목 [/]
  inprogress_items=$(grep -E '^\- \[/\]' "$SCHEDULE" \
    | sed 's/^- \[\/\] \[.*\] //' \
    | sed 's/ `[^`]*`//g' \
    | sed 's/ #[^ ]*//' \
    | head -7)
fi

completed_count=$(echo "$completed_items" | grep -c . || true)
inprogress_count=$(echo "$inprogress_items" | grep -c . || true)

# ── 다음 우선순위 항목 ────────────────────────────────────
next_items=""
if [ -f "$SCHEDULE" ]; then
  next_items=$(grep -E '^\- \[ \] \[높\]' "$SCHEDULE" \
    | sed 's/^- \[ \] \[높\] //' \
    | sed 's/ `[^`]*`//g' \
    | sed 's/ #[^ ]*//' \
    | head -5)
fi

# ── session.md 파싱 (지난 N일 세션 수) ────────────────────
SESSION_FILE="$REPO_DIR/session.md"
session_count=0
device_summary=""

if [ -f "$SESSION_FILE" ]; then
  # 지난 DAYS일 내 세션 헤더 수집
  recent_sessions=$(grep -E "^## \[${WEEK_START:0:7}" "$SESSION_FILE" | head -20 || true)
  session_count=$(echo "$recent_sessions" | grep -c . || true)

  # 기기별 집계
  mac_mini=$(echo "$recent_sessions" | grep -c "Mac mini" || true)
  mac_air=$(echo "$recent_sessions" | grep -c "Mac Air" || true)
  windows=$(echo "$recent_sessions" | grep -c "Windows" || true)
  m4=$(echo "$recent_sessions" | grep -c "(M4)" || true)

  parts=()
  [ "$mac_mini" -gt 0 ] && parts+=("Mac mini ${mac_mini}회")
  [ "$mac_air" -gt 0 ]  && parts+=("Mac Air ${mac_air}회")
  [ "$windows" -gt 0 ]  && parts+=("Windows ${windows}회")
  [ "$m4" -gt 0 ]       && parts+=("M4 ${m4}회")

  if [ "${#parts[@]}" -gt 0 ]; then
    device_summary=$(IFS=" · "; echo "${parts[*]}")
  else
    device_summary="기록 없음"
  fi
fi

# ── 리포트 조립 ────────────────────────────────────────────
build_list() {
  local items="$1"
  local prefix="$2"
  local result=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # 긴 줄 자르기
    short="${line:0:50}"
    [ ${#line} -gt 50 ] && short="${short}…"
    result+="${prefix} ${short}"$'\n'
  done <<< "$items"
  echo "$result"
}

completed_list=$(build_list "$completed_items" "✅")
inprogress_list=$(build_list "$inprogress_items" "🔄")
next_list=$(build_list "$next_items" "🎯")

REPORT="📊 <b>주간 운영 리포트</b>
${WEEK_LABEL}
━━━━━━━━━━━━━━━━━━━━

✅ <b>완료 (${completed_count}건)</b>
${completed_list}
🔄 <b>진행 중 (${inprogress_count}건)</b>
${inprogress_list}
🎯 <b>다음 우선순위 [높]</b>
${next_list}
━━━━━━━━━━━━━━━━━━━━
⏱ 세션 ${session_count}회 · ${device_summary}
🤖 COO 에이전트 자동 생성"

# ── 출력 / 전송 ────────────────────────────────────────────
echo "$REPORT"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo "[DRY-RUN] Telegram 전송 건너뜀"
  exit 0
fi

bash "$SCRIPT_DIR/telegram-send.sh" --message "$REPORT"
