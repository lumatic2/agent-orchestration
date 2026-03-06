#!/bin/bash
# tax_agent.sh — 회계사 AI 에이전트
# 사용법: bash tax_agent.sh "질문" [--planby] [--pro] [--save] [--capture] [--title "제목"]
#
# 옵션:
#   --planby   플랜바이 AnythingLLM 문서에서 관련 컨텍스트 검색 후 포함
#   --pro      Gemini 2.5 Pro 사용 (심층 분석, 일 100회 제한)
#   --save     결과를 Notion에 자동 저장 (PERSONAL_NOTION_TOKEN 필요)
#   --capture  Claude Code가 결과를 받아 검토하는 모드 (interactive 프롬프트 제거)
#   --title    Notion 저장 시 제목 (기본: 질문 앞 30자)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PERSONA_FILE="$REPO_DIR/agents/accountant_persona.md"

QUESTION=""
USE_PLANBY=false
MODEL="gemini-2.5-flash"
BACKEND="gemini"
SAVE_NOTION=false
SAVE_TITLE=""
CAPTURE_MODE=false
BRIEF_MODE=false

PREV_ARG=""
for arg in "$@"; do
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
      elif [ -z "$QUESTION" ]; then
        QUESTION="$arg"
      fi
      ;;
  esac
  PREV_ARG="$arg"
done

if [ -z "$QUESTION" ]; then
  echo "사용법: bash tax_agent.sh \"질문\" [--planby] [--pro] [--save] [--title \"제목\"]"
  echo ""
  echo "예시:"
  echo "  bash tax_agent.sh \"R&D 세액공제 신청 요건이 뭐야?\""
  echo "  bash tax_agent.sh \"TIPS 정부보조금 회계처리 방법\" --planby"
  echo "  bash tax_agent.sh \"법인세 이월결손금 공제 한도\" --pro"
  echo "  bash tax_agent.sh \"R&D 공제 분석\" --save --title \"R&D 세액공제 검토\""
  exit 1
fi

# Load persona
if [ ! -f "$PERSONA_FILE" ]; then
  echo "❌ 페르소나 파일 없음: $PERSONA_FILE"
  exit 1
fi
PERSONA=$(cat "$PERSONA_FILE")

# Load knowledge files
KNOWLEDGE_DIR="$REPO_DIR/agents/knowledge"
KNOWLEDGE=""
STALE_DAYS=90
NOW=$(date +%s)
for kfile in "$KNOWLEDGE_DIR/tax_core.md" "$KNOWLEDGE_DIR/tax_incentives.md" "$KNOWLEDGE_DIR/vat.md"; do
  if [ -f "$kfile" ]; then
    KNOWLEDGE="$KNOWLEDGE
$(cat "$kfile")
"
    MTIME=$(stat -f %m "$kfile" 2>/dev/null || stat -c %Y "$kfile" 2>/dev/null)
    if [ -n "$MTIME" ]; then
      AGE=$(( (NOW - MTIME) / 86400 ))
      [ "$AGE" -gt "$STALE_DAYS" ] && echo "⚠️  지식파일 오래됨 (${AGE}일): $(basename $kfile) — 내용 검토 필요" >&2
    fi
  fi
done

# Optionally query Planby RAG
PLANBY_CONTEXT=""
if [ "$USE_PLANBY" = true ]; then
  echo "🔍 플랜바이 문서 검색 중..."
  RAW=$(bash "$SCRIPT_DIR/planby_ask.sh" "$QUESTION" 3 2>/dev/null)
  if [ -n "$RAW" ] && echo "$RAW" | grep -q "청크"; then
    PLANBY_CONTEXT="## 플랜바이 관련 문서 (참고용)
$RAW
---
"
  fi
fi

# Build prompt
KNOWLEDGE_BLOCK=""
if [ -n "$KNOWLEDGE" ]; then
  KNOWLEDGE_BLOCK="## 핵심 세법 지식 (참고용)
$KNOWLEDGE
---

"
fi

BRIEF_INSTRUCTION=""
[ "$BRIEF_MODE" = true ] && BRIEF_INSTRUCTION="## 답변 형식
핵심만 bullet 3~5개로 요약. 총 200자 이내. 상세 설명 생략.

---

"

PROMPT="$PERSONA

---

${KNOWLEDGE_BLOCK}${PLANBY_CONTEXT}${BRIEF_INSTRUCTION}## 질문
$QUESTION"

if [ "$CAPTURE_MODE" = false ]; then
  echo "💼 회계사 AI 처리 중 ($BACKEND / $MODEL)..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
else
  echo "💼 회계사 AI ($BACKEND / $MODEL)..." >&2
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
    bash "$SCRIPT_DIR/feedback.sh" --log "tax" "" "$QUESTION" "$RATING" "$FB_NOTE"
  fi

  echo "💡 다음 단계:"
  echo "   Notion 저장:      bash tax_agent.sh \"질문\" --save [--title \"제목\"]"
  echo "   메모리 기록:      bash memory_update.sh \"recent_decisions\" \"tax: 내용\""
  echo "   심층 분석:        bash tax_agent.sh \"질문\" --pro"
  echo "   품질 통계:        bash feedback.sh --stats"
fi

if [ "$SAVE_NOTION" = true ]; then
  [ -z "$SAVE_TITLE" ] && SAVE_TITLE="세무: $(echo "$QUESTION" | cut -c1-30)"
  bash "$SCRIPT_DIR/save_to_notion.sh" \
    --agent tax \
    --title "$SAVE_TITLE" \
    --content "$OUTPUT"
fi
