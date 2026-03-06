#!/bin/bash
# ask.sh — 단일 진입점. 질문만 입력하면 적합한 전문가 에이전트 자동 선택
#
# 사용법: bash ask.sh "질문" [--planby] [--pro] [--save] [--follow] [--session NAME]
#
# 옵션:
#   --follow          마지막 Q&A를 컨텍스트로 포함 (1-turn 연속)
#   --session NAME    named 세션으로 최근 3턴 컨텍스트 유지 (logs/sessions/NAME.jsonl)
#
# 출력 마지막 줄 (Claude Code가 읽는 상태 마커):
#   <<<DIRECT>>>         — 수치/법적 판단 없음, Claude는 relay만
#   <<<REVIEW_NEEDED>>>  — 수치/금액/법적 판단 포함, Claude가 검토

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$REPO_DIR/logs/ask_history.jsonl"
SESSION_DIR="$REPO_DIR/logs/sessions"
mkdir -p "$REPO_DIR/logs" "$SESSION_DIR"

QUESTION=""
EXTRA_ARGS=()
USE_PRO=false
FOLLOW_MODE=false
SESSION_NAME=""

PREV_ARG=""
for arg in "$@"; do
  case "$arg" in
    --pro)     USE_PRO=true; EXTRA_ARGS+=("$arg") ;;
    --planby|--save|--brief) EXTRA_ARGS+=("$arg") ;;
    --follow)  FOLLOW_MODE=true ;;
    --session) ;;
    --*)       EXTRA_ARGS+=("$arg") ;;
    *)
      if [ "$PREV_ARG" = "--session" ]; then
        SESSION_NAME="$arg"
      elif [ -z "$QUESTION" ]; then
        QUESTION="$arg"
      fi
      ;;
  esac
  PREV_ARG="$arg"
done

if [ -z "$QUESTION" ]; then
  echo "사용법: bash ask.sh \"질문\" [--planby] [--pro] [--save] [--follow] [--session NAME]"
  echo ""
  echo "예시:"
  echo "  bash ask.sh \"창업감면 요건이 뭐야?\""
  echo "  bash ask.sh \"IFRS 16 리스 회계처리\" --planby"
  echo "  bash ask.sh \"상속세 절세 방법은?\" --pro"
  echo "  bash ask.sh \"그러면 이월결손금은?\" --follow"
  echo "  bash ask.sh \"다음 질문\" --session planby_audit"
  exit 1
fi

# 원본 질문 보존 (멀티턴 컨텍스트 주입 전)
ORIG_QUESTION="$QUESTION"

# ─── 검토 필요 여부 자동 판단 (원본 질문 기준) ───────────────
NEEDS_REVIEW=false

echo "$ORIG_QUESTION" | grep -qE '[0-9]억|[0-9]만원|[0-9]천원|[0-9]백만|[0-9]%|세율|공제액|공제한도|세액|납부액|환급액|이월결손금|과세표준|영업이익|당기순이익|절세액|감면액' && NEEDS_REVIEW=true
echo "$ORIG_QUESTION" | grep -qE '재무제표|회계기준|계정과목|감사|결산|재무상태|손익계산|현금흐름|자본변동|주석공시|내부통제|회계처리|분개|오류|잘못' && NEEDS_REVIEW=true
echo "$ORIG_QUESTION" | grep -qE '가능(한지|여부|해[?]?$)|합법|위법|요건(충족|해당)|해당(되|여부)|적용(되|여부)|위반(여부|인지)|불법|허용(되|여부)|면제(여부|되)|의무(인지|여부)|처벌' && NEEDS_REVIEW=true

# ─── 복합 도메인 자동 체인 감지 ──────────────────────────────
detect_chain() {
  local q="$1"
  local has_tax=false has_ifrs=false has_deal=false
  local has_wealth=false has_audit=false has_comm=false

  echo "$q" | grep -qiE '법인세|세금|세액공제|세율|세무신고|조특법' && has_tax=true
  echo "$q" | grep -qiE 'IFRS|리스.*회계|수익인식.*기준|회계기준.*처리' && has_ifrs=true
  echo "$q" | grep -qiE 'M&A|인수합병|실사|매각|딜' && has_deal=true
  echo "$q" | grep -qiE '상속|증여|가업승계' && has_wealth=true
  echo "$q" | grep -qiE '회계감사|외부감사|내부통제' && has_audit=true
  echo "$q" | grep -qiE '주주간계약|정관|지배구조' && has_comm=true

  $has_ifrs  && $has_tax    && echo "expert:ifrs_advisory tax"          && return
  $has_deal  && $has_tax    && echo "expert:deal_advisory tax"           && return
  $has_wealth && $has_comm  && echo "expert:wealth_tax expert:commercial_law" && return
  $has_wealth && $has_tax   && echo "expert:wealth_tax tax"              && return
  $has_audit && $has_ifrs   && echo "expert:audit expert:ifrs_advisory"  && return
}

# ─── 키워드 기반 단일 에이전트 라우팅 (0초, 비용 0) ──────────
route_agent() {
  local q="$1"
  echo "$q" | grep -qiE '세무조사|탈세|과세처분|경정청구|세무불복|세무대리인'         && echo "tax_investigation"  && return
  echo "$q" | grep -qiE '이전가격|국제조세|해외법인|조세조약|해외소득|이중과세'        && echo "international_tax"  && return
  echo "$q" | grep -qiE '상속세|증여세|상속|증여|가업승계|비상장주식.*증여'            && echo "wealth_tax"         && return
  echo "$q" | grep -qiE '법인세|부가세|소득세|세액공제|세금|세무|세율|창업감면|R&D공제|고용세액|이월결손|과세표준|납세|환급|세무신고|조특법|원천징수' && echo "tax" && return
  echo "$q" | grep -qiE 'IFRS|K-IFRS|리스.*회계|금융상품.*회계|충당부채|회계기준|중소기업회계|수익인식기준' && echo "ifrs_advisory" && return
  echo "$q" | grep -qiE '외부감사|감사절차|대손충당금|내부통제|내부회계|감사보고서|회계감사|감사인|재무제표.*감사|감사.*재무제표|감사 ' && echo "audit" && return
  echo "$q" | grep -qiE '기업가치|밸류에이션|DCF|PER|EV.EBITDA|가치평가|멀티플|주식가치평가' && echo "valuation" && return
  echo "$q" | grep -qiE '횡령|회계부정|분식회계|내부고발|부정행위|조작.*장부'         && echo "forensic"           && return
  echo "$q" | grep -qiE 'M&A|인수합병|실사|due diligence|Due Diligence|매각|딜클로징' && echo "deal_advisory"      && return
  echo "$q" | grep -qiE '주주간계약|정관|이사회|상법|법인설립|지배구조|주식매매계약'   && echo "commercial_law"     && return
  echo "$q" | grep -qiE '금리|환율|인플레이션|GDP|경기침체|통화정책|기준금리|거시경제' && echo "economics"          && return
  echo "$q" | grep -qiE '건강|증상|질병|번아웃|피로|스트레스|병원|의사|치료|수면'     && echo "doctor"             && return
  echo "$q" | grep -qiE '노동법|해고|임금체불|계약위반|손해배상|소송|형사|민사|법적책임' && echo "lawyer"           && return
  echo "$q" | grep -qiE '전략|비즈니스모델|스타트업|SaaS|OKR|마케팅|브랜딩|경쟁전략|성장전략' && echo "business"   && return
  echo "tax"
}

# ─── --planby 허용 에이전트 (재무/세무/법률 도메인만) ─────────
PLANBY_AGENTS="tax audit ifrs_advisory valuation deal_advisory commercial_law wealth_tax tax_investigation international_tax forensic"

_strip_planby() {
  local filtered=()
  for a in "${EXTRA_ARGS[@]}"; do
    [ "$a" != "--planby" ] && filtered+=("$a")
  done
  EXTRA_ARGS=("${filtered[@]}")
}

# ─── 에이전트 실행 (ANSI 제거 + 에러 핸들링) ─────────────────
_run_agent() {
  local agent="$1"; shift
  local args=("$@")
  local out

  if [ "$agent" = "tax" ]; then
    out=$(bash "$SCRIPT_DIR/tax_agent.sh" "$QUESTION" "${args[@]}" 2>/dev/null | \
          sed 's/\x1b\[[0-9;]*[mABCDEFGHJKSTfhilnprsu]//g; s/\x1b(B//g')
  else
    out=$(bash "$SCRIPT_DIR/expert_agent.sh" "$agent" "$QUESTION" "${args[@]}" 2>/dev/null | \
          sed 's/\x1b\[[0-9;]*[mABCDEFGHJKSTfhilnprsu]//g; s/\x1b(B//g')
  fi

  # 빈 응답 감지
  if [ -z "$(echo "$out" | tr -d '[:space:]')" ]; then
    echo "⚠️  에이전트 응답 없음 ($agent). Gemini 오류 또는 rate limit 가능성." >&2
    echo "[ERROR] 응답을 받지 못했습니다. 잠시 후 재시도하거나 --pro 옵션을 사용해보세요."
    return 1
  fi

  echo "$out"
}

# ─── 멀티턴 컨텍스트 로드 ────────────────────────────────────
# 반환값: 컨텍스트 블록 문자열 (없으면 빈 문자열)
_load_context() {
  local mode="$1"   # "follow" | "session"
  local sfile="$2"  # session file path (mode=session 시 사용)
  local max_turns="$3"

  python3 - "$mode" "$sfile" "$LOG_FILE" "$max_turns" << 'PYEOF'
import sys, json, os

mode, sfile, logfile, max_turns = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

def load_entries(path, n):
    if not os.path.isfile(path):
        return []
    entries = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                entries.append(json.loads(line))
            except Exception:
                pass
    return entries[-n:]

if mode == "follow":
    entries = load_entries(logfile, 1)
elif mode == "session":
    entries = load_entries(sfile, max_turns)
else:
    entries = []

if not entries:
    sys.exit(0)

lines = ["## 이전 대화 컨텍스트", ""]
for e in entries:
    q = e.get("question", "").strip()
    r = e.get("response", "").strip()
    # 응답에서 상태 마커 제거
    r_lines = [l for l in r.splitlines() if not l.startswith("<<<") and not l.startswith("💼") and not l.startswith("━")]
    r = "\n".join(r_lines).strip()
    lines.append(f"**Q**: {q}")
    lines.append(f"**A**: {r[:1500]}")
    lines.append("")

lines.append("---")
lines.append("")
print("\n".join(lines))
PYEOF
}

# ─── 세션 저장 ───────────────────────────────────────────────
_save_session() {
  local sfile="$1"
  local respfile="$2"

  python3 - "$ORIG_QUESTION" "$sfile" "$respfile" << 'PYEOF'
import sys, json
from datetime import datetime, timezone

question, sfile, respfile = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    response = open(respfile, encoding='utf-8').read()
except Exception:
    response = ""

entry = {
  "ts":       datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
  "question": question,
  "response": response[:4000]
}
with open(sfile, 'a', encoding='utf-8') as f:
    f.write(json.dumps(entry, ensure_ascii=False) + '\n')
PYEOF
}

# ─── 응답 로컬 저장 ───────────────────────────────────────────
# stdin 충돌 방지: heredoc(Python 코드)과 pipe가 충돌하므로 tmpfile 경유
_save_history() {
  local agent="$1"
  local review="$2"
  local respfile="$3"   # 응답 내용이 저장된 tmpfile 경로

  python3 - "$ORIG_QUESTION" "$agent" "$review" "$LOG_FILE" "$respfile" << 'PYEOF'
import sys, json
from datetime import datetime, timezone

question, agent, review, logfile, respfile = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
try:
    response = open(respfile, encoding='utf-8').read()
except Exception:
    response = ""

entry = {
  "ts":       datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
  "question": question,
  "agent":    agent,
  "review":   review,
  "response": response[:4000]
}
with open(logfile, 'a', encoding='utf-8') as f:
    f.write(json.dumps(entry, ensure_ascii=False) + '\n')
PYEOF
}

# ─── 메인 실행 ───────────────────────────────────────────────
EXTRA_ARGS+=("--capture")

# ─── 멀티턴: 컨텍스트 주입 ───────────────────────────────────
SESSION_FILE=""
if [ -n "$SESSION_NAME" ]; then
  SESSION_FILE="$SESSION_DIR/${SESSION_NAME}.jsonl"
fi

PRIOR_CONTEXT=""
if [ "$FOLLOW_MODE" = true ]; then
  PRIOR_CONTEXT=$(_load_context "follow" "" 1)
  [ -n "$PRIOR_CONTEXT" ] && echo "[FOLLOW] 이전 Q&A 컨텍스트 로드됨" >&2
elif [ -n "$SESSION_NAME" ]; then
  PRIOR_CONTEXT=$(_load_context "session" "$SESSION_FILE" 3)
  [ -n "$PRIOR_CONTEXT" ] && echo "[SESSION:$SESSION_NAME] 이전 컨텍스트 로드됨" >&2
fi

if [ -n "$PRIOR_CONTEXT" ]; then
  QUESTION="$PRIOR_CONTEXT$QUESTION"
fi

CHAIN_AGENTS=$(detect_chain "$ORIG_QUESTION")

if [ -n "$CHAIN_AGENTS" ]; then
  # 복합 도메인 → chain.sh
  echo "[AUTO] 복합 도메인 감지 → 체인 실행: $CHAIN_AGENTS" >&2
  PRO_FLAG=""
  $USE_PRO && PRO_FLAG="--pro"

  OUTPUT=$(bash "$SCRIPT_DIR/chain.sh" "$QUESTION" $CHAIN_AGENTS --capture $PRO_FLAG 2>/dev/null | \
           sed 's/\x1b\[[0-9;]*[mABCDEFGHJKSTfhilnprsu]//g; s/\x1b(B//g')

  DISPLAY_AGENT="chain:$CHAIN_AGENTS"
else
  # 단일 에이전트
  AGENT=$(route_agent "$ORIG_QUESTION")
  echo "[AUTO] $AGENT 에이전트 선택됨 (키워드 라우팅)" >&2

  # --planby 무관 에이전트에서 필터링
  if ! echo "$PLANBY_AGENTS" | grep -qw "$AGENT"; then
    if echo "${EXTRA_ARGS[*]}" | grep -q "\-\-planby"; then
      echo "ℹ️  $AGENT 에이전트는 --planby 미지원 → 무시" >&2
      _strip_planby
    fi
  fi

  OUTPUT=$(_run_agent "$AGENT" "${EXTRA_ARGS[@]}") || {
    echo "<<<ERROR>>>"
    exit 1
  }
  DISPLAY_AGENT="$AGENT"
fi

# ─── 출력 ─────────────────────────────────────────────────────
echo "$OUTPUT"

# 응답 저장 (tmpfile 경유)
REVIEW_STATUS="DIRECT"
[ "$NEEDS_REVIEW" = true ] && REVIEW_STATUS="REVIEW_NEEDED"
_RESP_TMP=$(mktemp)
echo "$OUTPUT" > "$_RESP_TMP"
_save_history "$DISPLAY_AGENT" "$REVIEW_STATUS" "$_RESP_TMP"

# 세션 모드: sessions/NAME.jsonl에도 저장
if [ -n "$SESSION_FILE" ]; then
  _save_session "$SESSION_FILE" "$_RESP_TMP"
fi

rm -f "$_RESP_TMP"

# 상태 마커 (마지막 줄)
echo ""
if [ "$NEEDS_REVIEW" = true ]; then
  echo "<<<REVIEW_NEEDED>>>"
else
  echo "<<<DIRECT>>>"
fi
