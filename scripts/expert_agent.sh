#!/bin/bash
# expert_agent.sh — 전문직 AI 에이전트 (범용)
# 사용법: bash expert_agent.sh [전문가유형] "질문" [--planby] [--pro] [--save]
#
# 전문가 유형: doctor | lawyer | tax (회계사는 tax_agent.sh 참고)
#
# 옵션:
#   --planby   플랜바이 AnythingLLM 문서에서 관련 컨텍스트 검색 후 포함
#   --pro      Gemini 2.5 Pro 사용 (심층 분석, 일 100회 제한)
#   --save     결과를 Notion에 자동 저장
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
MODEL="gemini-2.5-flash"
BACKEND="gemini"
SAVE_NOTION=false
SAVE_TITLE=""
USE_PLANBY=false
CAPTURE_MODE=false
BRIEF_MODE=false

PREV_ARG=""
for arg in "${@:3}"; do
  case "$arg" in
    --planby)  USE_PLANBY=true ;;
    --pro)     MODEL="gemini-2.5-pro" ;;
    --codex)   BACKEND="codex"; MODEL="gpt-5.2" ;;
    --save)    SAVE_NOTION=true ;;
    --capture) CAPTURE_MODE=true ;;
    --brief)   BRIEF_MODE=true ;;
    --title)   ;;
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
  valuation)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/valuation_formulas.md" "$KNOWLEDGE_DIR/ifrs_key.md") ;;
  ifrs_advisory|kicpa)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/ifrs_key.md" "$KNOWLEDGE_DIR/ifrs_advanced.md") ;;
  wealth_tax)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/inheritance_gift_tax.md" "$KNOWLEDGE_DIR/valuation_formulas.md" "$KNOWLEDGE_DIR/tax_incentives.md") ;;
  tax_investigation)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/tax_core.md" "$KNOWLEDGE_DIR/tax_incentives.md" "$KNOWLEDGE_DIR/vat.md") ;;
  international_tax)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/international_tax_rules.md" "$KNOWLEDGE_DIR/tax_core.md") ;;
  commercial_law)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/commercial_law_company.md") ;;
  forensic)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/fraud_detection.md" "$KNOWLEDGE_DIR/commercial_law_company.md") ;;
  deal_advisory)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/valuation_formulas.md" "$KNOWLEDGE_DIR/financial_strategy.md" "$KNOWLEDGE_DIR/startup_finance.md" "$KNOWLEDGE_DIR/capital_markets.md") ;;
  business)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/business_strategy.md" "$KNOWLEDGE_DIR/startup_finance.md" "$KNOWLEDGE_DIR/management_accounting.md") ;;
  doctor)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/medical_guidelines.md") ;;
  economics)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/macro_indicators.md") ;;
  lawyer)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/labor_civil_law.md" "$KNOWLEDGE_DIR/commercial_law_company.md") ;;
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

# Optionally query Planby RAG
PLANBY_BLOCK=""
if [ "$USE_PLANBY" = true ]; then
  echo "🔍 플랜바이 문서 검색 중..."
  if bash -c "curl -s http://localhost:3001/api/ping 2>/dev/null | grep -q online"; then
    PLANBY_CTX=$(bash "$SCRIPT_DIR/planby_ask.sh" "$QUESTION" 3 2>/dev/null)
    if [ -n "$PLANBY_CTX" ]; then
      PLANBY_BLOCK="## 플랜바이 관련 문서 (AnythingLLM)\n$PLANBY_CTX\n---\n\n"
    fi
  else
    echo "⚠️  AnythingLLM 서버 미응답 — 컨텍스트 없이 진행"
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

${KNOWLEDGE_BLOCK}$(printf '%b' "$PLANBY_BLOCK")## 질문
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

_TMP=$(mktemp)
if [ "$BACKEND" = "codex" ]; then
  codex exec -c model="$MODEL" -c 'approval_policy="never"' "$PROMPT" | tee "$_TMP"
else
  gemini --yolo -m "$MODEL" -p "$PROMPT" | tee "$_TMP"
fi
OUTPUT=$(cat "$_TMP"); rm -f "$_TMP"

if [ "$CAPTURE_MODE" = false ]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # 품질 평가 (5초 타임아웃, Enter=스킵)
  RATING=""
  read -t 5 -p "📊 품질 평가 (1-5, Enter=스킵): " RATING 2>/dev/null || true
  if [[ "$RATING" =~ ^[1-5]$ ]]; then
    read -t 10 -p "   메모 (Enter=없음): " FB_NOTE 2>/dev/null || FB_NOTE=""
    bash "$SCRIPT_DIR/feedback.sh" --log "expert" "$EXPERT" "$QUESTION" "$RATING" "$FB_NOTE"
  fi

  echo "💡 다음 단계:"
  echo "   Notion 저장:   bash expert_agent.sh $EXPERT \"질문\" --save [--title \"제목\"]"
  echo "   메모리 기록:   bash memory_update.sh \"recent_decisions\" \"expert/$EXPERT: 내용\""
  echo "   심층 분석:     bash expert_agent.sh $EXPERT \"질문\" --pro"
  echo "   플랜바이 연동: bash expert_agent.sh $EXPERT \"질문\" --planby"
  echo "   품질 통계:     bash feedback.sh --stats"
fi

if [ "$SAVE_NOTION" = true ]; then
  [ -z "$SAVE_TITLE" ] && SAVE_TITLE="$EXPERT: $(echo "$QUESTION" | cut -c1-30)"
  bash "$SCRIPT_DIR/save_to_notion.sh" \
    --agent expert \
    --title "$SAVE_TITLE" \
    --content "$OUTPUT"
fi
