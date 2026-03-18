#!/bin/bash
# ── check-slides.sh ───────────────────────────────────────────────────
# 슬라이드 HTML 파일에 대해 CHK-01~08 자가검증 실행
# Usage: bash check-slides.sh <html_file>
# 참조: slides_config.yaml > brief_checklist

HTML="$1"

if [ -z "$HTML" ] || [ ! -f "$HTML" ]; then
  echo "Usage: bash check-slides.sh <html_file>"
  exit 1
fi

PASS=0
FAIL=0
NA=0

# grep -c 결과를 안전하게 정수로 변환
cnt() { grep -c "$1" "$2" 2>/dev/null | tr -d ' \n' || echo "0"; }
cnt_e() { grep -cE "$1" "$2" 2>/dev/null | tr -d ' \n' || echo "0"; }

pass() { echo "  ✓ $1 PASS — $2"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1 FAIL — $2"; FAIL=$((FAIL+1)); }
na()   { echo "  ~ $1 N/A  — $2"; NA=$((NA+1)); }

echo ""
echo "=== CHK 자가검증: $(basename "$HTML") ==="
echo ""

# CHK-01: 슬라이드 고정 높이 (height:720px)
C=$(cnt 'height:.*720px' "$HTML")
[ "$C" -ge 1 ] && pass "CHK-01" "height:720px ${C}회" \
               || fail "CHK-01" "height:720px 없음 (AP-04) — .slide에 추가 필요"

# CHK-02: Pattern C 패널 flex centering
PANEL_C=$(grep -oE '\.(panel-[a-z]+|left-panel|right-panel)\s*\{' "$HTML" 2>/dev/null | wc -l | tr -d ' \n')
CENTER_C=$(cnt 'justify-content:.*center' "$HTML")
if [ "$CENTER_C" -ge 1 ] && [ "$CENTER_C" -ge "$PANEL_C" ]; then
  pass "CHK-02" "패널 ${PANEL_C}개, justify-content:center ${CENTER_C}회"
else
  fail "CHK-02" "패널 ${PANEL_C}개 대비 justify-content:center ${CENTER_C}회 — 패널 누락 의심 (AP-08)"
fi

# CHK-03: 카드 그리드 align-content:stretch
STRETCH_C=$(cnt 'align-content:.*stretch' "$HTML")
GRID_C=$(cnt_e 'card-grid|\.bento|\.trio' "$HTML")
if [ "$GRID_C" -eq 0 ]; then
  na "CHK-03" "카드 그리드 없음"
elif [ "$STRETCH_C" -ge 1 ]; then
  pass "CHK-03" "align-content:stretch ${STRETCH_C}회 (그리드 ${GRID_C}개)"
else
  fail "CHK-03" "card-grid ${GRID_C}개인데 align-content:stretch 없음 (AP-11)"
fi

# CHK-04: 배지 display:inline-block
C=$(cnt 'display:.*inline-block' "$HTML")
[ "$C" -ge 1 ] && pass "CHK-04" "display:inline-block ${C}회" \
               || fail "CHK-04" "배지에 inline-block 없음 (AP-12)"

# CHK-05: 한국어 word-break:keep-all
C=$(cnt 'word-break:.*keep-all' "$HTML")
[ "$C" -ge 1 ] && pass "CHK-05" "word-break:keep-all ${C}회" \
               || fail "CHK-05" "word-break:keep-all 전역 미적용 (AP-13)"

# CHK-06: height:100% — position:absolute 패널 외 사용 금지
H100=$(cnt 'height:.*100%' "$HTML")
ABS=$(cnt 'position:.*absolute' "$HTML")
if [ "$H100" -le "$ABS" ]; then
  pass "CHK-06" "height:100% ${H100}회 ≤ position:absolute ${ABS}회"
else
  fail "CHK-06" "height:100% ${H100}회 > position:absolute ${ABS}회 — flex child 오용 의심 (AP-01)"
fi

# CHK-07: 타임라인 노드 원형 (타임라인 있을 때만)
TL=$(cnt_e 'timeline|\.node\b' "$HTML")
if [ "$TL" -eq 0 ]; then
  na "CHK-07" "타임라인 없음"
else
  C=$(cnt 'border-radius:.*50%' "$HTML")
  [ "$C" -ge 1 ] && pass "CHK-07" "border-radius:50% ${C}회 (노드 원형)" \
                 || fail "CHK-07" "타임라인 있는데 border-radius:50% 없음 (AP-18)"
fi

# CHK-07b: AP-20 카드 내 텍스트 하단 쏠림 방지 (justify-content:space-between)
CARD_C=$(cnt_e '\.card|\.stat-card|\.b-card|\.trio-card' "$HTML")
SB_C=$(cnt 'justify-content:.*space-between' "$HTML")
if [ "$CARD_C" -eq 0 ]; then
  na "CHK-09" "카드 클래스 없음"
elif [ "$SB_C" -ge 1 ]; then
  pass "CHK-09" "카드 ${CARD_C}개, justify-content:space-between ${SB_C}회 (AP-20)"
else
  fail "CHK-09" "카드 ${CARD_C}개인데 justify-content:space-between 없음 → 텍스트 하단 쏠림 (AP-20)"
fi

# CHK-08: 다크 테마 선 색상 rgba 사용
DARK=$(cnt_e '#0A0A|#0F17|#1A1A|#14141|#1C0F|#121212' "$HTML")
if [ "$DARK" -eq 0 ]; then
  na "CHK-08" "다크 테마 아님"
else
  C=$(cnt 'rgba(' "$HTML")
  [ "$C" -ge 2 ] && pass "CHK-08" "다크 테마, rgba() ${C}회 (선 대비 확보)" \
                 || fail "CHK-08" "다크 테마인데 rgba() ${C}회 — 선 대비 미확보 (AP-17)"
fi

# ── 결과 요약 ────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────"
printf "  결과: PASS %d / FAIL %d / N/A %d\n" "$PASS" "$FAIL" "$NA"
if [ "$FAIL" -eq 0 ]; then
  echo "  → 전항목 통과. 렌더 진행 가능."
else
  echo "  → FAIL 항목 수정 후 재확인 필요."
fi
echo "────────────────────────────────────"
echo ""

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
