#!/bin/bash
# kicpa_agent.sh — 재무회계·원가관리 전문가 AI
# 사용법: bash kicpa_agent.sh [영역] "질문" [--pro] [--save]
#
# 영역 (생략 가능):
#   financial   재무회계 (K-IFRS)
#   cost        원가관리회계
#   tax         세법 (→ tax_agent.sh 연계)
#   finance     재무관리
#   audit       감사론·내부통제
#
# 옵션:
#   --pro    Gemini 2.5 Pro 사용 (복잡한 계산·심층 분석)
#   --save   결과를 Notion에 저장

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PERSONA_FILE="$REPO_DIR/agents/kicpa_persona.md"

subject_label() {
  case "$1" in
    financial) echo "재무회계" ;;
    cost)      echo "원가관리회계" ;;
    tax)       echo "세법" ;;
    finance)   echo "재무관리" ;;
    audit)     echo "감사론" ;;
    *)         echo "재무회계 종합" ;;
  esac
}

# ── arg 파싱 ─────────────────────────────────────────────
SUBJECT=""
QUESTION=""
MODEL="gemini-2.5-flash"
SAVE_NOTION=false
SAVE_TITLE=""

SUBJECTS="financial cost tax finance audit"
PREV_ARG=""

for arg in "$@"; do
  case "$arg" in
    --pro)   MODEL="gemini-2.5-pro" ;;
    --save)  SAVE_NOTION=true ;;
    --title) ;;
    *)
      if [ "$PREV_ARG" = "--title" ]; then
        SAVE_TITLE="$arg"
      elif echo "$SUBJECTS" | grep -qw "$arg"; then
        SUBJECT="$arg"
      elif [ -z "$QUESTION" ]; then
        QUESTION="$arg"
      fi
      ;;
  esac
  PREV_ARG="$arg"
done

# ── 세법은 tax_agent.sh로 위임 ───────────────────────────
if [ "$SUBJECT" = "tax" ]; then
  exec bash "$SCRIPT_DIR/tax_agent.sh" "$QUESTION" ${SAVE_NOTION:+--save} ${SAVE_TITLE:+--title "$SAVE_TITLE"}
fi

# ── 사용법 ───────────────────────────────────────────────
if [ -z "$QUESTION" ]; then
  echo "사용법: bash kicpa_agent.sh [영역] \"질문\" [--pro] [--save]"
  echo ""
  echo "영역:"
  echo "  financial  재무회계 (K-IFRS, 연결, 금융상품)"
  echo "  cost       원가관리회계 (ABC, 표준원가, CVP)"
  echo "  tax        세법 → tax_agent.sh로 자동 연결"
  echo "  finance    재무관리 (DCF, 자본구조, 파생상품)"
  echo "  audit      감사론·내부통제"
  echo "  (생략 시 종합)"
  echo ""
  echo "예시:"
  echo "  bash kicpa_agent.sh financial \"사업결합 취득법 분개 방법\""
  echo "  bash kicpa_agent.sh cost \"표준원가 차이분석 3분법으로 풀어줘\" --pro"
  echo "  bash kicpa_agent.sh finance \"WACC 계산 예제\" --save"
  echo "  bash kicpa_agent.sh \"리스 분류 기준 K-IFRS 16호\""
  exit 1
fi

# ── 페르소나 로드 ─────────────────────────────────────────
if [ ! -f "$PERSONA_FILE" ]; then
  echo "❌ 페르소나 파일 없음: $PERSONA_FILE"
  exit 1
fi
PERSONA=$(cat "$PERSONA_FILE")

# ── 영역 컨텍스트 ─────────────────────────────────────────
SUBJECT_LABEL=$(subject_label "$SUBJECT")
SUBJECT_HINT=""
if [ -n "$SUBJECT" ]; then
  SUBJECT_HINT="## 분야
현재 분야: **$SUBJECT_LABEL**
이 분야의 기준서·이론·실무 적용을 중심으로 상세히 답변하세요.

"
fi

# ── 프롬프트 구성 ─────────────────────────────────────────
PROMPT="$PERSONA

---

${SUBJECT_HINT}## 질문
$QUESTION"

echo "📊 재무회계 전문가 ($SUBJECT_LABEL / $MODEL)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

_TMP=$(mktemp)
gemini --yolo -m "$MODEL" -p "$PROMPT" | tee "$_TMP"
OUTPUT=$(cat "$_TMP"); rm -f "$_TMP"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 관련 에이전트:"
echo "   세무 실무:   bash tax_agent.sh \"질문\""
echo "   법령 검색:   bash law_agent.sh \"질문\" --law 상법"
echo "   정부회계:    bash expert_agent.sh gov_accounting \"질문\""
echo "   Notion 저장: bash kicpa_agent.sh $SUBJECT \"질문\" --save"

if [ "$SAVE_NOTION" = true ]; then
  [ -z "$SAVE_TITLE" ] && SAVE_TITLE="재무: $SUBJECT_LABEL — $(echo "$QUESTION" | cut -c1-25)"
  bash "$SCRIPT_DIR/save_to_notion.sh" \
    --agent expert \
    --title "$SAVE_TITLE" \
    --content "$OUTPUT"
fi
