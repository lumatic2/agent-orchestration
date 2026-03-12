#!/bin/bash
# expert_agent.sh — 전문직 AI 에이전트 (범용)
# 사용법: bash expert_agent.sh [전문가유형] "질문" [옵션]
#
# 전문가 유형: doctor | lawyer | tax (회계사는 tax_agent.sh 참고)
#
# 옵션:
#   --planby     플랜바이 로컬 파일에서 관련 문서를 직접 첨부
#   --pro        gpt-5.4 extra-high reasoning 사용
#   --gemini     Gemini 2.5 Flash 사용 (기본: Codex gpt-5.4)
#   --no-review  Claude 검토 단계 생략
#   --save       결과를 Notion에 자동 저장
#
# 예시:
#   bash expert_agent.sh doctor "두통이 3일째 계속되는데 원인이 뭘까요?"
#   bash expert_agent.sh lawyer "직원 해고 시 주의사항 알려줘" --pro
#   bash expert_agent.sh ifrs_advisory "리스 회계처리 방법" --planby
#   bash expert_agent.sh list   # 사용 가능한 전문가 목록

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
EXPERTS_DIR="$REPO_DIR/agents/experts"

EXPERT="${1:-}"
QUESTION="${2:-}"
MODEL="gpt-5.4"
REASONING="high"
BACKEND="codex"
SAVE_NOTION=false
SAVE_TITLE=""
USE_PLANBY=false
CAPTURE_MODE=false
BRIEF_MODE=false
NO_REVIEW=false

PREV_ARG=""
for arg in "${@:3}"; do
  case "$arg" in
    --planby)    USE_PLANBY=true ;;
    --pro)       REASONING="extra-high" ;;
    --gemini)    BACKEND="gemini"; MODEL="gemini-2.5-flash" ;;
    --save)      SAVE_NOTION=true ;;
    --capture)   CAPTURE_MODE=true ;;
    --brief)     BRIEF_MODE=true ;;
    --no-review) NO_REVIEW=true ;;
    --title)     ;;
    *)
      if [ "$PREV_ARG" = "--title" ]; then
        SAVE_TITLE="$arg"
      fi
      ;;
  esac
  PREV_ARG="$arg"
done

# List available experts
if [ "$EXPERT" = "list" ] || [ -z "$EXPERT" ]; then
  echo "📋 사용 가능한 전문가 AI:"
  echo ""
  for f in "$EXPERTS_DIR"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .md)
    title=$(head -1 "$f" | sed 's/# //' | sed 's/ — 시스템 프롬프트//')
    echo "  $name   → $title"
  done
  echo "  tax    → 세무회계 전문가 (scripts/tax_agent.sh)"
  echo ""
  echo "사용법: bash expert_agent.sh [전문가] \"질문\" [--planby] [--pro]"
  exit 0
fi

PERSONA_FILE="$EXPERTS_DIR/$EXPERT.md"

# Alias: tax → redirect to tax_agent.sh
if [ "$EXPERT" = "tax" ]; then
  shift
  bash "$SCRIPT_DIR/tax_agent.sh" "$@"
  exit $?
fi

if [ ! -f "$PERSONA_FILE" ]; then
  echo "❌ 전문가 없음: $EXPERT"
  echo "   bash expert_agent.sh list 로 목록 확인"
  exit 1
fi

if [ -z "$QUESTION" ]; then
  echo "사용법: bash expert_agent.sh $EXPERT \"질문\""
  exit 1
fi

PERSONA=$(cat "$PERSONA_FILE")

# Load relevant knowledge files based on expert type
KNOWLEDGE_DIR="$REPO_DIR/agents/knowledge"
KNOWLEDGE_FILES=()
case "$EXPERT" in
  audit)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/audit_standards.md" "$KNOWLEDGE_DIR/ifrs_key.md") ;;
  accounting_advisory)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/ifrs_key.md" "$KNOWLEDGE_DIR/ifrs_advanced.md" "$KNOWLEDGE_DIR/management_accounting.md" "$KNOWLEDGE_DIR/sme_accounting.md") ;;
  legal_advisory)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/commercial_law_company.md" "$KNOWLEDGE_DIR/labor_civil_law.md") ;;
  deal_valuation)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/valuation_formulas.md" "$KNOWLEDGE_DIR/financial_strategy.md" "$KNOWLEDGE_DIR/startup_finance.md" "$KNOWLEDGE_DIR/capital_markets.md") ;;
  wealth_tax)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/inheritance_gift_tax.md" "$KNOWLEDGE_DIR/valuation_formulas.md" "$KNOWLEDGE_DIR/tax_incentives.md" "$KNOWLEDGE_DIR/tax_personal.md") ;;
  tax_investigation)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/tax_core.md" "$KNOWLEDGE_DIR/tax_incentives.md" "$KNOWLEDGE_DIR/vat.md") ;;
  international_tax)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/international_tax_rules.md" "$KNOWLEDGE_DIR/tax_core.md") ;;
  forensic)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/fraud_detection.md" "$KNOWLEDGE_DIR/commercial_law_company.md") ;;
  business)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/business_strategy.md" "$KNOWLEDGE_DIR/startup_finance.md" "$KNOWLEDGE_DIR/management_accounting.md" "$KNOWLEDGE_DIR/planby_framework.md") ;;
  doctor)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/medical_guidelines.md") ;;
  economics)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/macro_indicators.md") ;;
  gov_accounting)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/management_accounting.md" "$KNOWLEDGE_DIR/audit_standards.md" "$KNOWLEDGE_DIR/gov_accounting_standards.md") ;;
esac

KNOWLEDGE=""
STALE_DAYS=90
NOW=$(date +%s)
for kfile in "${KNOWLEDGE_FILES[@]}"; do
  if [ -f "$kfile" ]; then
    KNOWLEDGE="$KNOWLEDGE
$(cat "$kfile")
"
    # 최신성 경고: 파일 수정일이 STALE_DAYS일 이상 경과 시
    MTIME=$(stat -f %m "$kfile" 2>/dev/null || stat -c %Y "$kfile" 2>/dev/null)
    if [ -n "$MTIME" ]; then
      AGE=$(( (NOW - MTIME) / 86400 ))
      if [ "$AGE" -gt "$STALE_DAYS" ]; then
        echo "⚠️  지식파일 오래됨 (${AGE}일): $(basename $kfile) — 내용 검토 필요" >&2
      fi
    fi
  fi
done

KNOWLEDGE_BLOCK=""
if [ -n "$KNOWLEDGE" ]; then
  KNOWLEDGE_BLOCK="## 핵심 지식 (참고용)
$KNOWLEDGE
---

"
fi

# Optionally attach Planby local files
PLANBY_FILES=()
if [ "$USE_PLANBY" = true ]; then
  echo "🔍 플랜바이 로컬 문서 검색 중..."
  mapfile -t PLANBY_FILES < <(bash "$SCRIPT_DIR/planby_context.sh" "$QUESTION" 2>/dev/null)
  if [ ${#PLANBY_FILES[@]} -gt 0 ]; then
    echo "📎 연결 파일 ${#PLANBY_FILES[@]}개:"
    for f in "${PLANBY_FILES[@]}"; do echo "   - $(basename "$f")"; done
  else
    echo "⚠️  관련 파일 없음 — 컨텍스트 없이 진행"
  fi
fi

BRIEF_INSTRUCTION=""
[ "$BRIEF_MODE" = true ] && BRIEF_INSTRUCTION="

## ⚠️ OVERRIDE — 간결 모드
위의 모든 답변 형식 지시를 무시한다. 아래 구조만 사용할 것.
서술·배경설명·예시 전면 생략. 수치·법령·기준서 조항은 반드시 포함.

**핵심 판단** — 1~2문장 (결론만)
**핵심 기준/수치** — bullet 4~6개 (구체적 수치, 법령 조항)
**실무 주의사항** — bullet 1~2개"

PROMPT="$PERSONA

---

${KNOWLEDGE_BLOCK}## 질문
$QUESTION
${BRIEF_INSTRUCTION}"

TITLE=$(head -1 "$PERSONA_FILE" | sed 's/# //' | sed 's/ — 시스템 프롬프트//')

if [ "$CAPTURE_MODE" = false ]; then
  echo "👨‍⚕️ $TITLE 처리 중 ($BACKEND / $MODEL)..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
else
  echo "👨‍⚕️ $TITLE ($BACKEND / $MODEL)..." >&2
fi

# ── 전문가 호출 함수 ─────────────────────────────────────────
run_expert() {
  local prompt="$1"
  local tmp; tmp=$(mktemp)
  if [ "$BACKEND" = "codex" ]; then
    codex exec -c model="$MODEL" -c model_reasoning_effort="$REASONING" \
      -c 'approval_policy="never"' "$prompt" | tee "$tmp"
  else
    local gemini_flags=()
    for f in "${PLANBY_FILES[@]}"; do gemini_flags+=("-f" "$f"); done
    gemini --yolo -m "$MODEL" "${gemini_flags[@]}" -p "$prompt" | tee "$tmp"
  fi
  cat "$tmp"; rm -f "$tmp"
}

# ── Claude 검토 함수 ──────────────────────────────────────────
run_review() {
  local answer="$1" question="$2"
  echo ""
  echo "── Claude 검토 중... ────────────────────────────────────"
  claude --dangerously-skip-permissions -p \
"전문가 AI[$TITLE]의 답변을 검토해라.

[원본 질문]
$question

[전문가 답변]
$answer

검토 기준:
- 법령/기준서 인용 오류 또는 누락
- 한국 실무상 놓친 중요 포인트
- 수치나 기한 등 사실 오류 가능성
- 신뢰도: High / Medium / Low 판정

bullet 5개 이내로 간결하게. 문제 없으면 '✓ 검토 이상 없음' 한 줄로."
  echo "────────────────────────────────────────────────────────"
}

# ── 첫 번째 답변 ──────────────────────────────────────────────
if [ "$CAPTURE_MODE" = false ]; then
  echo "👨‍💼 $TITLE 처리 중 ($BACKEND / $MODEL, reasoning=$REASONING)..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
else
  echo "👨‍💼 $TITLE ($BACKEND / $MODEL)..." >&2
fi

OUTPUT=$(run_expert "$PROMPT")

[ "$CAPTURE_MODE" = false ] && echo "" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Claude 검토
[ "$NO_REVIEW" = false ] && [ "$CAPTURE_MODE" = false ] && run_review "$OUTPUT" "$QUESTION"

# Notion 저장
if [ "$SAVE_NOTION" = true ]; then
  [ -z "$SAVE_TITLE" ] && SAVE_TITLE="$EXPERT: $(echo "$QUESTION" | cut -c1-30)"
  bash "$SCRIPT_DIR/save_to_notion.sh" --agent expert --title "$SAVE_TITLE" --content "$OUTPUT"
fi

[ "$CAPTURE_MODE" = true ] && exit 0

# ── 멀티턴 대화 루프 ──────────────────────────────────────────
HISTORY="## 질문
$QUESTION

## 답변
$OUTPUT"

while true; do
  echo ""
  read -r -p "추가 질문 (종료: q 또는 Enter): " FOLLOWUP 2>/dev/null || break
  [ -z "$FOLLOWUP" ] || [ "$FOLLOWUP" = "q" ] && break

  FOLLOW_PROMPT="$PERSONA

---

${KNOWLEDGE_BLOCK}## 대화 기록
$HISTORY

---

## 새 질문
$FOLLOWUP"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  FOLLOW_OUTPUT=$(run_expert "$FOLLOW_PROMPT")
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  [ "$NO_REVIEW" = false ] && run_review "$FOLLOW_OUTPUT" "$FOLLOWUP"

  HISTORY="$HISTORY

## 추가 질문
$FOLLOWUP

## 답변
$FOLLOW_OUTPUT"
done
