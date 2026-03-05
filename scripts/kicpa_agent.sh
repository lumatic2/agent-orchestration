#!/bin/bash
# kicpa_agent.sh — 재무회계 전문가 AI (expert_agent.sh 위임 shim)
#
# 사용법: bash kicpa_agent.sh [영역] "질문" [--pro] [--save] [--title "제목"]
#
# 영역:
#   financial  재무회계 (K-IFRS) → expert:kicpa
#   cost       원가관리회계       → expert:kicpa
#   finance    재무관리           → expert:kicpa
#   audit      감사론·내부통제    → expert:audit
#   tax        세법               → tax_agent.sh
#   (생략)     재무회계 종합      → expert:kicpa

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── arg 파싱 ─────────────────────────────────────────────
SUBJECT=""
QUESTION=""
PASS_ARGS=()
SUBJECTS="financial cost tax finance audit"
PREV_ARG=""

for arg in "$@"; do
  case "$arg" in
    --pro|--save) PASS_ARGS+=("$arg") ;;
    --title)      PASS_ARGS+=("$arg") ;;
    *)
      if [ "$PREV_ARG" = "--title" ]; then
        PASS_ARGS+=("$arg")
      elif echo "$SUBJECTS" | grep -qw "$arg"; then
        SUBJECT="$arg"
      elif [ -z "$QUESTION" ]; then
        QUESTION="$arg"
      fi
      ;;
  esac
  PREV_ARG="$arg"
done

if [ -z "$QUESTION" ]; then
  echo "사용법: bash kicpa_agent.sh [영역] \"질문\" [--pro] [--save]"
  echo ""
  echo "영역 → 라우팅:"
  echo "  financial  재무회계 (K-IFRS, 연결)     → expert:kicpa"
  echo "  cost       원가관리회계 (ABC, CVP)       → expert:kicpa"
  echo "  finance    재무관리 (DCF, 자본구조)      → expert:kicpa"
  echo "  audit      감사론·내부통제               → expert:audit"
  echo "  tax        세법                          → tax_agent.sh"
  echo "  (생략)     재무회계 종합                 → expert:kicpa"
  echo ""
  echo "또는 직접: bash expert_agent.sh kicpa \"질문\""
  exit 1
fi

# ── 영역별 라우팅 ─────────────────────────────────────────
case "$SUBJECT" in
  tax)
    exec bash "$SCRIPT_DIR/tax_agent.sh" "$QUESTION" "${PASS_ARGS[@]}"
    ;;
  audit)
    exec bash "$SCRIPT_DIR/expert_agent.sh" audit "$QUESTION" "${PASS_ARGS[@]}"
    ;;
  *)
    # financial | cost | finance | (생략) → kicpa
    exec bash "$SCRIPT_DIR/expert_agent.sh" kicpa "$QUESTION" "${PASS_ARGS[@]}"
    ;;
esac
