#!/bin/bash
# bench_experts.sh — 전문가 에이전트 배치 품질 테스트
# 사용법:
#   bash bench_experts.sh              # 전체 에이전트 테스트
#   bash bench_experts.sh ifrs_advisory  # 특정 에이전트만
#   bash bench_experts.sh --all        # 전체 (--all 명시)
#   bash bench_experts.sh --stats      # 누적 점수 요약만 출력

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── 표준 테스트 질문 ──────────────────────────────────────────
declare -A TEST_QUESTIONS=(
  [audit]="매출채권 대손충당금 감사 절차를 설명해줘"
  [valuation]="스타트업 DCF 밸류에이션 핵심 단계는?"
  [ifrs_advisory]="IFRS 16 리스부채 최초 인식 방법은?"
  [wealth_tax]="비상장주식 증여세 계산 방법은?"
  [tax_investigation]="세무조사 사전 대응 체크리스트 알려줘"
  [international_tax]="이전가격 문서화 의무 기준은?"
  [commercial_law]="주주간계약서 핵심 조항은?"
  [forensic]="횡령 회계부정 징후 식별 방법은?"
  [deal_advisory]="M&A 실사(Due Diligence) 주요 항목은?"
  [business]="SaaS 스타트업 Rule of 40 개선 전략은?"
  [economics]="금리 인상이 스타트업 밸류에이션에 미치는 영향은?"
  [doctor]="번아웃 초기 증상과 대처법은?"
  [lawyer]="스타트업 공동창업자 계약서 핵심 조항은?"
)

# ─── --stats 단독 실행 ────────────────────────────────────────
if [ "${1:-}" = "--stats" ]; then
  bash "$SCRIPT_DIR/feedback.sh" --stats
  exit 0
fi

# ─── 대상 에이전트 결정 ───────────────────────────────────────
TARGET="${1:-}"
if [ -z "$TARGET" ] || [ "$TARGET" = "--all" ]; then
  AGENTS=("${!TEST_QUESTIONS[@]}")
else
  if [ -z "${TEST_QUESTIONS[$TARGET]+_}" ]; then
    echo "❌ 알 수 없는 에이전트: $TARGET"
    echo "   사용 가능: ${!TEST_QUESTIONS[*]}"
    exit 1
  fi
  AGENTS=("$TARGET")
fi

TOTAL=${#AGENTS[@]}
PASS=0
FAIL=0
IDX=0

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 전문가 배치 테스트 시작 (${TOTAL}개 에이전트)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── 각 에이전트 테스트 ───────────────────────────────────────
for AGENT in "${AGENTS[@]}"; do
  IDX=$((IDX + 1))
  QUESTION="${TEST_QUESTIONS[$AGENT]}"

  echo "[$IDX/$TOTAL] 🔬 $AGENT"
  echo "  질문: $QUESTION"
  echo "  ──────────────────────────────────────"

  # 응답 생성 (출력 포함)
  bash "$SCRIPT_DIR/expert_agent.sh" "$AGENT" "$QUESTION" 2>&1
  STATUS=$?

  echo ""
  if [ $STATUS -ne 0 ]; then
    echo "  ⚠️  실행 오류 (exit $STATUS) — 스킵"
    FAIL=$((FAIL + 1))
    echo ""
    continue
  fi

  # 품질 평가 (10초 타임아웃)
  RATING=""
  read -t 10 -p "  📊 이 응답 품질 점수 (1-5, Enter=스킵): " RATING 2>/dev/null || true
  echo ""

  if [[ "$RATING" =~ ^[1-5]$ ]]; then
    read -t 10 -p "  메모 (Enter=없음): " FB_NOTE 2>/dev/null || FB_NOTE=""
    bash "$SCRIPT_DIR/feedback.sh" --log "bench" "$AGENT" "$QUESTION" "$RATING" "$FB_NOTE"
    PASS=$((PASS + 1))
  else
    echo "  [스킵] 평점 없이 진행"
    PASS=$((PASS + 1))
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
done

# ─── 최종 요약 ────────────────────────────────────────────────
echo "✅ 배치 테스트 완료"
echo "   실행: ${PASS}개 성공 / ${FAIL}개 오류 / 전체 ${TOTAL}개"
echo ""
echo "📊 누적 품질 통계:"
bash "$SCRIPT_DIR/feedback.sh" --stats
