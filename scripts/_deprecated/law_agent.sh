#!/bin/bash
# law_agent.sh — 한국 법령 검색 에이전트
# 사용법: bash law_agent.sh "질문" [--law 소득세법] [--rag] [--save]
#
# 모드:
#   (기본)  Gemini가 법제처(law.go.kr) 실시간 검색 위임 (API 키 불필요)
#   --rag   ChromaDB 로컬 RAG (knowledge 파일 + 법제처 API 검색)
#
# 옵션:
#   --law <법령>   특정 법령 한정 검색 (약어 가능: 소득세, 법인세, 부가세 등)
#   --rag          RAG 모드 (로컬 ChromaDB 검색 + Gemini 합성)
#   --seed         RAG 초기 인덱싱 (knowledge/*.md, API key 불필요)
#   --fetch <법령> Gemini로 법령 조문 검색 → 인덱싱 (쉼표로 여러 법령)
#   --pdf <경로>   PDF 파일 인덱싱 (검증된 법령집·기준서)
#   --index        RAG 법제처 API 인덱싱 (LAW_API_OC 필요)
#   --list         인덱싱 현황 보기
#   --save         결과를 Notion에 저장
#   --pro          Gemini 2.5 Pro 사용

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# venv Python (chromadb 설치됨)
VENV_PYTHON="$SCRIPT_DIR/../.venv-law/bin/python3"
if [ ! -f "$VENV_PYTHON" ]; then
  VENV_PYTHON="python3"  # fallback
fi

QUERY=""
LAW_FILTER=""
MODE="search"   # search | rag | seed | fetch | pdf | index | list
FETCH_TARGET=""
PDF_PATH=""
MODEL="gemini-2.5-flash"
SAVE_NOTION=false
SAVE_TITLE=""

PREV_ARG=""
for arg in "$@"; do
  case "$arg" in
    --rag)   MODE="rag" ;;
    --seed)  MODE="seed" ;;
    --fetch) MODE="fetch" ;;
    --pdf)   MODE="pdf" ;;
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
      elif [ "$PREV_ARG" = "--fetch" ]; then
        FETCH_TARGET="$arg"
      elif [ "$PREV_ARG" = "--pdf" ]; then
        PDF_PATH="$arg"
      elif [ -z "$QUERY" ]; then
        QUERY="$arg"
      fi
      ;;
  esac
  PREV_ARG="$arg"
done

# ── 인덱싱 현황 ───────────────────────────────────────
if [ "$MODE" = "list" ]; then
  "$VENV_PYTHON" "$SCRIPT_DIR/law_rag.py" --list
  exit 0
fi

# ── 시드 인덱싱 (knowledge/*.md, API key 불필요) ───────
if [ "$MODE" = "seed" ]; then
  echo "📚 knowledge 파일 인덱싱 중..."
  "$VENV_PYTHON" "$SCRIPT_DIR/law_rag.py" --seed
  exit 0
fi

# ── Gemini 검색 → 인덱싱 ──────────────────────────────
if [ "$MODE" = "fetch" ]; then
  TARGET="${FETCH_TARGET:-${QUERY:-}}"
  if [ -z "$TARGET" ]; then
    echo "사용법: bash law_agent.sh --fetch \"소득세법\""
    echo "        bash law_agent.sh --fetch \"소득세법,법인세법,부가가치세법\""
    exit 1
  fi
  echo "🔍 Gemini로 법령 검색 → 인덱싱: $TARGET"
  "$VENV_PYTHON" "$SCRIPT_DIR/law_rag.py" --fetch "$TARGET"
  exit 0
fi

# ── PDF 인덱싱 ────────────────────────────────────────
if [ "$MODE" = "pdf" ]; then
  if [ -z "$PDF_PATH" ]; then
    echo "사용법: bash law_agent.sh --pdf /path/to/file.pdf [--law \"법령명\"]"
    exit 1
  fi
  echo "📄 PDF 인덱싱: $PDF_PATH"
  if [ -n "$LAW_FILTER" ]; then
    "$VENV_PYTHON" "$SCRIPT_DIR/law_rag.py" --pdf "$PDF_PATH" --law "$LAW_FILTER"
  else
    "$VENV_PYTHON" "$SCRIPT_DIR/law_rag.py" --pdf "$PDF_PATH"
  fi
  exit 0
fi

# ── 법제처 API 인덱싱 (LAW_API_OC 필요) ───────────────
if [ "$MODE" = "index" ]; then
  if [ -z "${LAW_API_OC:-}" ]; then
    echo "❌ LAW_API_OC 환경변수 필요 (법제처 API 인증키)"
    echo "   https://open.law.go.kr 에서 발급 후:"
    echo "   export LAW_API_OC=your_email_id"
    exit 1
  fi
  echo "📚 법령 인덱싱 중 (법제처 API)..."
  "$VENV_PYTHON" "$SCRIPT_DIR/law_rag.py" --index \
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
  echo "  bash law_agent.sh \"소득세법 원천징수\" --rag       # 로컬 RAG 검색"
  echo "  bash law_agent.sh --seed                          # RAG 초기 인덱싱 (API key 불필요)"
  echo "  bash law_agent.sh --fetch \"소득세법,법인세법\"    # Gemini 검색 → 인덱싱"
  echo "  bash law_agent.sh --pdf 소득세법.pdf              # PDF 인덱싱"
  echo "  bash law_agent.sh --list                          # 인덱싱 현황"
  exit 1
fi

# ── RAG 모드 ──────────────────────────────────────────
if [ "$MODE" = "rag" ]; then
  echo "⚖️  법령 RAG 검색 중..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  _TMP=$(mktemp)
  if [ -n "$LAW_FILTER" ]; then
    "$VENV_PYTHON" "$SCRIPT_DIR/law_rag.py" --ask "$QUERY" --law "$LAW_FILTER" | tee "$_TMP"
  else
    "$VENV_PYTHON" "$SCRIPT_DIR/law_rag.py" --ask "$QUERY" | tee "$_TMP"
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
