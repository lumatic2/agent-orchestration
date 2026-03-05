#!/bin/bash
# expert_agent.sh — 전문직 AI 에이전트 (범용)
# 사용법: bash expert_agent.sh [전문가유형] "질문" [--pro]
#
# 전문가 유형: doctor | lawyer | tax (회계사는 tax_agent.sh 참고)
#
# 예시:
#   bash expert_agent.sh doctor "두통이 3일째 계속되는데 원인이 뭘까요?"
#   bash expert_agent.sh lawyer "직원 해고 시 주의사항 알려줘" --pro
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

PREV_ARG=""
for arg in "${@:3}"; do
  case "$arg" in
    --pro)   MODEL="gemini-2.5-pro" ;;
    --codex) BACKEND="codex"; MODEL="gpt-5.2" ;;
    --save)  SAVE_NOTION=true ;;
    --title) ;;
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
  echo "사용법: bash expert_agent.sh [전문가] \"질문\" [--pro]"
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
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/audit_standards.md") ;;
  valuation)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/valuation_formulas.md" "$KNOWLEDGE_DIR/ifrs_key.md") ;;
  ifrs_advisory|kicpa)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/ifrs_key.md") ;;
  wealth_tax)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/inheritance_gift_tax.md" "$KNOWLEDGE_DIR/valuation_formulas.md" "$KNOWLEDGE_DIR/tax_incentives.md") ;;
  tax_investigation)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/tax_core.md" "$KNOWLEDGE_DIR/tax_incentives.md" "$KNOWLEDGE_DIR/vat.md") ;;
  international_tax)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/tax_core.md" "$KNOWLEDGE_DIR/vat.md") ;;
  commercial_law)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/commercial_law_company.md") ;;
  forensic)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/commercial_law_company.md" "$KNOWLEDGE_DIR/tax_core.md") ;;
  deal_advisory)
    KNOWLEDGE_FILES=("$KNOWLEDGE_DIR/valuation_formulas.md" "$KNOWLEDGE_DIR/commercial_law_company.md") ;;
esac

KNOWLEDGE=""
for kfile in "${KNOWLEDGE_FILES[@]}"; do
  if [ -f "$kfile" ]; then
    KNOWLEDGE="$KNOWLEDGE
$(cat "$kfile")
"
  fi
done

KNOWLEDGE_BLOCK=""
if [ -n "$KNOWLEDGE" ]; then
  KNOWLEDGE_BLOCK="## 핵심 지식 (참고용)
$KNOWLEDGE
---

"
fi

PROMPT="$PERSONA

---

${KNOWLEDGE_BLOCK}## 질문
$QUESTION"

TITLE=$(head -1 "$PERSONA_FILE" | sed 's/# //' | sed 's/ — 시스템 프롬프트//')
echo "👨‍⚕️ $TITLE 처리 중 ($BACKEND / $MODEL)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

_TMP=$(mktemp)
if [ "$BACKEND" = "codex" ]; then
  codex exec -c model="$MODEL" -c 'approval_policy="never"' "$PROMPT" | tee "$_TMP"
else
  gemini --yolo -m "$MODEL" -p "$PROMPT" | tee "$_TMP"
fi
OUTPUT=$(cat "$_TMP"); rm -f "$_TMP"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 다음 단계:"
echo "   Notion 저장:   bash expert_agent.sh $EXPERT \"질문\" --save [--title \"제목\"]"
echo "   메모리 기록:   bash memory_update.sh \"recent_decisions\" \"expert/$EXPERT: 내용\""
echo "   심층 분석:     bash expert_agent.sh $EXPERT \"질문\" --pro"

if [ "$SAVE_NOTION" = true ]; then
  [ -z "$SAVE_TITLE" ] && SAVE_TITLE="$EXPERT: $(echo "$QUESTION" | cut -c1-30)"
  bash "$SCRIPT_DIR/save_to_notion.sh" \
    --agent expert \
    --title "$SAVE_TITLE" \
    --content "$OUTPUT"
fi
