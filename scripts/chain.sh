#!/bin/bash
# chain.sh — 순차적 에이전트 체인 실행
#
# 사용법: bash chain.sh "질문" agent1 agent2 [agent3...] [--save] [--title "제목"] [--pro]
#
# 에이전트 형식:
#   tax                    → tax_agent.sh
#   expert:<유형>          → expert_agent.sh <유형>   (예: expert:audit, expert:valuation)
#   law                    → law_agent.sh
#   law:<법령명>           → law_agent.sh --law <법령명>
#
# 동작 방식:
#   1. 원래 질문으로 agent1 실행
#   2. agent1 결과를 컨텍스트로 추가해 agent2 실행
#   3. 누적 컨텍스트로 agent3 실행 (이하 동일)
#
# 예시:
#   bash chain.sh "R&D 세액공제 재무영향 분석" "expert:ifrs_advisory" "tax"
#   bash chain.sh "M&A 딜 검토" "expert:valuation" "expert:audit" --save
#   bash chain.sh "가업승계 절세 방안" "expert:wealth_tax" "tax" --pro --save

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# ─── 인수 파싱 ────────────────────────────────────────────────
QUESTION=""
AGENTS=()
SAVE_NOTION=false
SAVE_TITLE=""
USE_PRO=false
PREV_ARG=""

for arg in "$@"; do
  case "$arg" in
    --save)  SAVE_NOTION=true ;;
    --pro)   USE_PRO=true ;;
    --title) ;;
    *)
      if [ "$PREV_ARG" = "--title" ]; then
        SAVE_TITLE="$arg"
      elif [ -z "$QUESTION" ]; then
        QUESTION="$arg"
      else
        AGENTS+=("$arg")
      fi
      ;;
  esac
  PREV_ARG="$arg"
done

if [ -z "$QUESTION" ] || [ ${#AGENTS[@]} -eq 0 ]; then
  echo "사용법: bash chain.sh \"질문\" agent1 [agent2...] [--save] [--title \"제목\"] [--pro]"
  echo ""
  echo "에이전트 유형:"
  echo "  tax                세무회계 (tax_agent.sh)"
  echo "  expert:<유형>      전문직 (expert_agent.sh 유형)"
  echo "  law                법령 검색 (law_agent.sh)"
  echo ""
  echo "예시:"
  echo "  bash chain.sh \"R&D 세액공제 재무영향\" expert:ifrs_advisory tax"
  echo "  bash chain.sh \"가업승계 절세\" expert:wealth_tax tax --save"
  exit 1
fi

PRO_FLAG=""
[ "$USE_PRO" = true ] && PRO_FLAG="--pro"

# ─── 체인 실행 ────────────────────────────────────────────────
CONTEXT=""          # 누적 컨텍스트
CHAIN_LOG=""        # 전체 결과 (Notion 저장용)
STEP=0

echo "🔗 에이전트 체인 시작"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📌 질문: $QUESTION"
echo "📋 체인: ${AGENTS[*]}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for AGENT in "${AGENTS[@]}"; do
  STEP=$((STEP + 1))
  echo "┌─ STEP $STEP / ${#AGENTS[@]}: $AGENT"
  echo ""

  # ─── 에이전트별 질문 구성 ─────────────────────────────────
  if [ -n "$CONTEXT" ]; then
    FULL_QUESTION="$QUESTION

---

## 이전 분석 결과 (참고)
$CONTEXT"
  else
    FULL_QUESTION="$QUESTION"
  fi

  # ─── 에이전트 실행 ────────────────────────────────────────
  _TMP=$(mktemp)

  case "$AGENT" in
    tax)
      bash "$SCRIPT_DIR/tax_agent.sh" "$FULL_QUESTION" $PRO_FLAG 2>/dev/null | tee "$_TMP" ;;
    expert:*)
      ETYPE="${AGENT#expert:}"
      bash "$SCRIPT_DIR/expert_agent.sh" "$ETYPE" "$FULL_QUESTION" $PRO_FLAG 2>/dev/null | tee "$_TMP" ;;
    law:*)
      LNAME="${AGENT#law:}"
      bash "$SCRIPT_DIR/law_agent.sh" "$FULL_QUESTION" --law "$LNAME" 2>/dev/null | tee "$_TMP" ;;
    law)
      bash "$SCRIPT_DIR/law_agent.sh" "$FULL_QUESTION" 2>/dev/null | tee "$_TMP" ;;
    *)
      echo "⚠️  알 수 없는 에이전트: $AGENT (건너뜀)"
      rm -f "$_TMP"
      continue ;;
  esac

  STEP_OUTPUT=$(cat "$_TMP"); rm -f "$_TMP"

  # 다음 단계 안내 메시지 제거 (echo 라인들)
  STEP_OUTPUT=$(echo "$STEP_OUTPUT" | grep -v "^━" | grep -v "^💡 다음 단계" | grep -v "^ *Notion 저장" | grep -v "^ *메모리 기록" | grep -v "^ *심층 분석" | grep -v "^\[NOTION\]")

  # ─── 컨텍스트 누적 ────────────────────────────────────────
  CONTEXT="$CONTEXT

### [$AGENT] 분석
$STEP_OUTPUT"

  CHAIN_LOG="$CHAIN_LOG
## STEP $STEP: $AGENT

$STEP_OUTPUT

---
"
  echo ""
  echo "└─ STEP $STEP 완료"
  echo ""
done

# ─── 완료 메시지 ─────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 체인 완료 (${#AGENTS[@]}단계)"
echo ""
echo "💡 다음 단계:"
echo "   메모리 기록:  bash memory_update.sh \"recent_decisions\" \"chain: $QUESTION\""
if [ "$SAVE_NOTION" = false ]; then
  echo "   Notion 저장:  bash chain.sh \"질문\" ... --save"
fi

# ─── Notion 저장 ─────────────────────────────────────────────
if [ "$SAVE_NOTION" = true ]; then
  [ -z "$SAVE_TITLE" ] && SAVE_TITLE="체인분석: $(echo "$QUESTION" | cut -c1-30)"
  CHAIN_HEADER="# 에이전트 체인 분석

**질문**: $QUESTION
**체인**: ${AGENTS[*]}
**일시**: $(date '+%Y-%m-%d %H:%M')

---
"
  bash "$SCRIPT_DIR/save_to_notion.sh" \
    --agent expert \
    --title "$SAVE_TITLE" \
    --content "${CHAIN_HEADER}${CHAIN_LOG}"
fi
