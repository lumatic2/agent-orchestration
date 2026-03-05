#!/bin/bash
# law_agent.sh — 한국 법령 검색 에이전트
# 사용법: bash law_agent.sh "질문" [--law 소득세법] [--rag] [--save]
#
# 모드:
#   (기본)  Gemini가 법제처(law.go.kr) 실시간 검색 위임 (API 키 불필요)
#   --rag   ChromaDB 로컬 인덱스에서 검색 (law_rag.py, LAW_API_OC 필요)
#
# 옵션:
#   --law <법령>   특정 법령 한정 검색 (약어 가능: 소득세, 법인세, 부가세 등)
#   --rag          RAG 모드 (인덱싱된 법령 대상 정밀 검색)
#   --index        RAG 법령 인덱싱 (처음 한 번 실행)
#   --list         주요 법령 목록 보기
#   --save         결과를 Notion에 저장
#   --pro          Gemini 2.5 Pro 사용

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

QUERY=""
LAW_FILTER=""
MODE="search"   # search | rag | index | list
MODEL="gemini-2.5-flash"
SAVE_NOTION=false
SAVE_TITLE=""

PREV_ARG=""
for arg in "$@"; do
  case "$arg" in
    --rag)   MODE="rag" ;;
    --index) MODE="index" ;;
    --list)  MODE="list" ;;
    --pro)   MODEL="gemini-2.5-pro" ;;
    --save)  SAVE_NOTION=true ;;
    --law|--title) ;;
    *)
      if [ "$PREV_ARG" = "--law" ]; then
        LAW_FILTER="$arg"
      elif [ "$PREV_ARG" = "--title" ]; then
        SAVE_TITLE="$arg"
      elif [ -z "$QUERY" ]; then
        QUERY="$arg"
      fi
      ;;
  esac
  PREV_ARG="$arg"
done

# ── 법령 목록 ─────────────────────────────────────────
if [ "$MODE" = "list" ]; then
  python3 "$SCRIPT_DIR/law_search.py" --list
  exit 0
fi

# ── RAG 인덱싱 ────────────────────────────────────────
if [ "$MODE" = "index" ]; then
  if [ -z "$LAW_API_OC" ]; then
    echo "❌ LAW_API_OC 환경변수 필요 (법제처 API 인증키)"
    echo "   https://open.law.go.kr 에서 발급 후:"
    echo "   export LAW_API_OC=your_email_id"
    exit 1
  fi
  echo "📚 법령 인덱싱 중 (최초 1회 실행)..."
  python3 "$SCRIPT_DIR/law_rag.py" --index \
    --query "${QUERY:-소득세법,법인세법,부가가치세법,상법,조세특례제한법,국세기본법}"
  exit 0
fi

# ── 질문 필수 ─────────────────────────────────────────
if [ -z "$QUERY" ]; then
  echo "사용법: bash law_agent.sh \"질문\" [--law 법령명] [--rag] [--save]"
  echo ""
  echo "예시:"
  echo "  bash law_agent.sh \"원천징수 세율은?\""
  echo "  bash law_agent.sh \"배당소득 과세\" --law 법인세법"
  echo "  bash law_agent.sh \"R&D 세액공제 요건\" --law 조특법 --pro"
  echo "  bash law_agent.sh \"소득세법 원천징수\" --rag    # 로컬 RAG 검색"
  echo "  bash law_agent.sh --list                         # 법령 목록"
  echo "  bash law_agent.sh --index                        # RAG 인덱싱"
  exit 1
fi

# ── RAG 모드 ──────────────────────────────────────────
if [ "$MODE" = "rag" ]; then
  echo "⚖️  법령 RAG 검색 중..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  _TMP=$(mktemp)
  if [ -n "$LAW_FILTER" ]; then
    python3 "$SCRIPT_DIR/law_rag.py" --ask "$QUERY" --law "$LAW_FILTER" | tee "$_TMP"
  else
    python3 "$SCRIPT_DIR/law_rag.py" --ask "$QUERY" | tee "$_TMP"
  fi
  OUTPUT=$(cat "$_TMP"); rm -f "$_TMP"
else
  # ── Gemini 실시간 검색 모드 ───────────────────────────
  echo "⚖️  법령 검색 중 ($MODEL)..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  _TMP=$(mktemp)
  if [ -n "$LAW_FILTER" ]; then
    python3 "$SCRIPT_DIR/law_search.py" "$QUERY" --law "$LAW_FILTER" | tee "$_TMP"
  else
    python3 "$SCRIPT_DIR/law_search.py" "$QUERY" | tee "$_TMP"
  fi
  OUTPUT=$(cat "$_TMP"); rm -f "$_TMP"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 다음 단계:"
echo "   특정 법령 한정:  bash law_agent.sh \"질문\" --law 법인세법"
echo "   RAG 정밀 검색:   bash law_agent.sh \"질문\" --rag  (인덱싱 필요)"
echo "   세무 에이전트:   bash tax_agent.sh \"질문\"  (실무 해석)"
echo "   KICPA 학습:      bash kicpa_agent.sh tax \"질문\"  (시험 대비)"

if [ "$SAVE_NOTION" = true ]; then
  [ -z "$SAVE_TITLE" ] && SAVE_TITLE="법령: $(echo "$QUERY" | cut -c1-30)"
  bash "$SCRIPT_DIR/save_to_notion.sh" \
    --agent expert \
    --title "$SAVE_TITLE" \
    --content "$OUTPUT"
fi
