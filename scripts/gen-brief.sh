#!/bin/bash

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: bash gen-brief.sh \"주제명\" [슬라이드수=9]" >&2
  exit 1
fi

topic="$1"
slide_n="${2:-9}"

if ! [[ "$slide_n" =~ ^[0-9]+$ ]]; then
  echo "슬라이드 수는 숫자여야 합니다." >&2
  exit 1
fi

if [ "$slide_n" -lt 1 ]; then
  echo "슬라이드 수는 1 이상이어야 합니다." >&2
  exit 1
fi

if [ "$slide_n" -gt 9 ]; then
  slide_n=9
fi

topic_lc=$(printf '%s' "$topic" | tr '[:upper:]' '[:lower:]')

choose_preset() {
  local t="$1"

  if [[ "$t" == *"planby"* || "$t" == *"플랜바이"* || "$t" == *"plana"* ]]; then
    echo "planby_dark"
  elif [[ "$t" == *"커피"* || "$t" == *"카페"* || "$t" == *"원두"* || "$t" == *"브루잉"* || "$t" == *"바리스타"* ]]; then
    echo "dark_coffee"
  elif [[ "$t" == *"힙합"* || "$t" == *"트랩"* || "$t" == *"붐뱁"* || "$t" == *"뮤직"* || "$t" == *"음악"* || "$t" == *"랩"* ]]; then
    echo "dark_premium"
  elif [[ "$t" == *"미쉐린"* || "$t" == *"고급"* || "$t" == *"레스토랑"* || "$t" == *"와인"* || "$t" == *"파인다이닝"* || "$t" == *"호텔"* ]]; then
    echo "dark_gold"
  elif [[ "$t" == *"우주"* || "$t" == *"ai"* || "$t" == *"테크"* || "$t" == *"미래"* || "$t" == *"sf"* || "$t" == *"블록체인"* || "$t" == *"사이버"* ]]; then
    echo "dark_midnight"
  elif [[ "$t" == *"스포츠"* || "$t" == *"축구"* || "$t" == *"농구"* || "$t" == *"야구"* || "$t" == *"격투"* || "$t" == *"운동"* || "$t" == *"헬스"* ]]; then
    echo "light_red"
  elif [[ "$t" == *"환경"* || "$t" == *"건강"* || "$t" == *"자연"* || "$t" == *"esg"* || "$t" == *"성장"* || "$t" == *"웰니스"* || "$t" == *"농업"* ]]; then
    echo "light_green"
  elif [[ "$t" == *"금융"* || "$t" == *"기업"* || "$t" == *"투자"* || "$t" == *"ir"* || "$t" == *"컨설팅"* || "$t" == *"전략"* || "$t" == *"회계"* || "$t" == *"세무"* ]]; then
    echo "light_navy"
  elif [[ "$t" == *"여행"* || "$t" == *"음식"* || "$t" == *"요리"* || "$t" == *"골프"* || "$t" == *"라이프스타일"* || "$t" == *"관광"* ]]; then
    echo "light_warm"
  else
    echo "base_light"
  fi
}

preset=$(choose_preset "$topic_lc")

preset_css() {
  case "$1" in
    planby_dark)
      cat <<'CSS'
:root {
  --bg:#2C2C2E; --bg-card:#3C3C3E; --bg-card2:#48484A;
  --accent:#5E5CE6; --accent2:#4844D4;
  --text:#FFFFFF; --text-sub:#D1D1DB; --text-muted:#98989E;
  --border:rgba(94,92,230,0.25); --surface:#3C3C3E;
}
CSS
      ;;
    dark_coffee)
      cat <<'CSS'
:root {
  --bg:#1C0F07; --bg-card:#2C1A0E; --bg-card2:#3D2610;
  --accent:#D4A052; --accent2:#A07030;
  --text:#F5EBD8; --text-sub:#D4C4A8; --text-muted:#A89070;
  --border:rgba(212,160,82,0.25); --surface:#2C1A0E;
}
CSS
      ;;
    dark_premium)
      cat <<'CSS'
:root {
  --bg:#0A0A0F; --bg-card:#14141F; --bg-card2:#1E1E2E;
  --accent:#8B5CF6; --accent2:#6D28D9;
  --text:#F8F8F2; --text-sub:#BFBFD0; --text-muted:#9898B0;
  --border:rgba(255,255,255,0.10); --surface:#14141F;
}
CSS
      ;;
    dark_gold)
      cat <<'CSS'
:root {
  --bg:#0F172A; --bg-card:#1E293B; --bg-card2:#263348;
  --accent:#C9A84C; --accent2:#A07830;
  --text:#F8F4EE; --text-sub:#CBD5E1; --text-muted:#94A3B8;
  --border:rgba(201,168,76,0.20); --surface:#1E293B;
}
CSS
      ;;
    dark_midnight)
      cat <<'CSS'
:root {
  --bg:#0A1628; --bg-card:#0F2040; --bg-card2:#162952;
  --accent:#38BDF8; --accent2:#0284C7;
  --text:#F0F9FF; --text-sub:#BAE6FD; --text-muted:#7DD3FC;
  --border:rgba(56,189,248,0.15); --surface:#0F2040;
}
CSS
      ;;
    light_red)
      cat <<'CSS'
:root {
  --bg:#FFFFFF; --bg-card:#FFF5F5; --bg-card2:#FEE2E2;
  --accent:#DC2626; --accent2:#B91C1C;
  --text:#111827; --text-sub:#374151; --text-muted:#6B7280;
  --border:#FECACA; --surface:#FFF5F5;
}
CSS
      ;;
    light_green)
      cat <<'CSS'
:root {
  --bg:#FFFFFF; --bg-card:#F0FDF4; --bg-card2:#DCFCE7;
  --accent:#059669; --accent2:#047857;
  --text:#052E16; --text-sub:#166534; --text-muted:#6B7280;
  --border:#BBF7D0; --surface:#F0FDF4;
}
CSS
      ;;
    light_navy)
      cat <<'CSS'
:root {
  --bg:#FFFFFF; --bg-card:#EFF6FF; --bg-card2:#DBEAFE;
  --accent:#1E40AF; --accent2:#1D4ED8;
  --text:#0F172A; --text-sub:#1E3A5F; --text-muted:#64748B;
  --border:#BFDBFE; --surface:#EFF6FF;
}
CSS
      ;;
    light_warm)
      cat <<'CSS'
:root {
  --bg:#FFFBF5; --bg-card:#FEF3E2; --bg-card2:#FDE8C8;
  --accent:#D97706; --accent2:#B45309;
  --text:#1C1917; --text-sub:#44403C; --text-muted:#78716C;
  --border:#FDE68A; --surface:#FEF3E2;
}
CSS
      ;;
    *)
      cat <<'CSS'
:root {
  --bg:#FFFFFF; --bg-card:#F8FAFC; --bg-card2:#F1F5F9;
  --accent:#2563EB; --accent2:#1D4ED8;
  --text:#111827; --text-sub:#374151; --text-muted:#6B7280;
  --border:#E5E7EB; --surface:#F8FAFC;
}
CSS
      ;;
  esac
}

slug=$(printf '%s' "$topic_lc" | sed -E 's/[^[:alnum:]가-힣]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')
if [ -z "$slug" ]; then
  slug="brief"
fi

outfile="/tmp/${slug}-brief.md"
preset_block="$(preset_css "$preset")"

# ── Planby 전용 템플릿 ──────────────────────────────────────────────
if [ "$preset" = "planby_dark" ]; then

slide_patterns=(
  "Pattern C|magazine_split"
  "Pattern A|bento_grid"
  "Pattern C|2분할 (비교/대조)"
  "Pattern A|comparison_table"
  "Pattern A|zigzag_rows"
  "Pattern B|stat_trio"
  "Pattern A|timeline_flow"
  "Pattern C|3분할 big_statement"
  "Pattern C|three_split_verdict"
)

slide_sections=(
"### S1 — 타이틀 [Pattern C: magazine_split]
- 주제: ${topic}
- 좌 패널 58%: planby 로고(상단) + 주제 대형 타이틀 + 부제 1줄 + 날짜/버전
- 우 패널 42%: 인디고 퍼플(#5E5CE6) 곡선 웨이브 + 도트 장식 (SVG, 회사소개서 표지 스타일)
- AP-08 필수: 패널에 display:flex; flex-direction:column; justify-content:center"
"### S2 — TODO [Pattern A: bento_grid]
- badge: 현황 분석
- 제목: TODO
- 카드 3~4개: 각 카드 = 라벨(소형) + 핵심 수치/키워드(중대형, 인디고색) + 설명 2~3줄
- 반드시 이 CSS를 사용할 것:
  .b-card { display:flex; flex-direction:column; gap:10px; padding:28px 24px; height:100%; background:var(--bg-card); border-radius:12px; }
  .b-label { font-size:11px; color:var(--text-muted); font-weight:600; letter-spacing:0.06em; text-transform:uppercase; }
  .b-value { font-size:36px; font-weight:800; color:var(--accent); line-height:1.1; }
  .b-desc { font-size:12px; color:var(--text-sub); line-height:1.7; }
- ⚠️ justify-content:space-between 절대 금지. margin-top:auto 절대 금지
- 설명 텍스트는 2~3줄 분량으로 충분히 작성해 카드 공백 방지"
"### S3 — TODO [Pattern C: 2분할 (비교/대조)]
- badge: 핵심 비교
- 좌 패널 50%: badge + 제목 + 핵심 주장 3~4포인트
- 우 패널 50%: 대비 항목 or 데이터 시각화 (수치·그래프 대체 표현)
- AP-08 필수: 패널에 display:flex; flex-direction:column; justify-content:center"
"### S4 — TODO [Pattern A: comparison_table]
- badge: 기능 구성
- 제목: TODO
- 표: 3~4행 × 3열 비교 (항목명 | Before | After 또는 A안 | B안)
- 헤더 배경: var(--accent) 인디고"
"### S5 — TODO [Pattern A: zigzag_rows]
- badge: 실행 흐름
- 제목: TODO
- 행 3개: 각 행 = 아이콘 원형(인디고) + 단계명 + 설명 1~2줄
- 연결선: 인디고 점선 (--border 색상)"
"### S6 — TODO [Pattern B: stat_trio]
- badge: 운영 지표
- 제목: TODO
- 핵심 수치 3개: 각 카드 = 숫자(초대형) + 액센트 구분선 + 라벨 + 설명 텍스트 2~3줄
- 반드시 이 HTML 구조를 사용할 것:
  <div class=\"stat-card\">
    <div class=\"stat-number\">숫자</div>
    <div class=\"stat-divider\"></div>
    <div class=\"stat-label\">라벨</div>
    <div class=\"stat-desc\">설명 2~3줄 (충분한 텍스트로 카드 채울 것)</div>
  </div>
- 반드시 이 CSS를 사용할 것:
  .stat-card { display:flex; flex-direction:column; gap:12px; padding:32px 28px; height:100%; background:var(--bg-card); border-radius:12px; }
  .stat-number { font-size:72px; font-weight:800; color:var(--accent); line-height:1; }
  .stat-divider { width:36px; height:3px; background:var(--accent); border-radius:2px; opacity:0.6; }
  .stat-label { font-size:14px; color:var(--text-sub); font-weight:600; }
  .stat-desc { font-size:12px; color:var(--text-muted); line-height:1.7; }
- ⚠️ justify-content:space-between 절대 금지. margin-top:auto 절대 금지"
"### S7 — TODO [Pattern A: timeline_flow]
- badge: 로드맵
- 제목: TODO
- 타임라인 4단계: 각 카드 = 날짜 + 인디고 점(노드) + 단계명 + 설명 3~4줄 (카드를 채울 충분한 텍스트 필수)
- 반드시 이 HTML 구조를 사용할 것:
  <div class=\"tl-card\">
    <div class=\"tl-date\">기간</div>
    <div class=\"tl-node\"></div>
    <div class=\"tl-title\">단계명</div>
    <div class=\"tl-body\">설명 3~4줄. 구체적 액션/파일명/수치 포함.</div>
  </div>
- 반드시 이 CSS를 사용할 것:
  .tl-card { display:flex; flex-direction:column; gap:10px; padding:24px 20px; height:100%; background:var(--bg-card); border-radius:12px; }
  .tl-date { font-size:11px; color:var(--text-muted); font-weight:500; }
  .tl-node { width:14px; height:14px; border-radius:50%; background:var(--accent); flex-shrink:0; }
  .tl-title { font-size:17px; font-weight:700; color:var(--text); }
  .tl-body { font-size:12px; color:var(--text-sub); line-height:1.7; }
- ⚠️ justify-content:space-between 절대 금지. margin-top:auto 절대 금지"
"### S8 — TODO [Pattern C: 3분할 big_statement]
- badge: 핵심 메시지
- 패널 CSS (반드시 준수):
  .slide-inner { display:flex; width:100%; height:100%; }
  .panel-left { width:30%; display:flex; flex-direction:column; justify-content:center; padding:48px 32px; background:var(--bg-card); }
  .panel-mid  { width:40%; display:flex; flex-direction:column; justify-content:center; padding:48px 32px; }
  .panel-right{ width:30%; display:flex; flex-direction:column; justify-content:center; padding:48px 32px; background:var(--bg-card2); }
- 좌 패널: badge + 핵심 메시지 대형(font-size:28px, font-weight:700, word-break:keep-all)
- 중앙 패널: 주요 근거 리스트 or 시각화 요소
- 우 패널: 보조 수치 or 요약 포인트 (번호 목록)"
"### S9 — TODO [Pattern C: three_split_verdict]
- 패널 CSS (반드시 준수):
  .slide-inner { display:flex; width:100%; height:100%; }
  .panel-left  { width:33%; display:flex; flex-direction:column; justify-content:center; padding:48px 36px; background:var(--bg-card); }
  .panel-mid   { width:34%; display:flex; flex-direction:column; justify-content:center; padding:48px 36px; }
  .panel-right { width:33%; display:flex; flex-direction:column; justify-content:center; padding:48px 36px; background:var(--bg-card2); }
- 좌 패널: 핵심 메시지 1문장 대형(font-size:26px, font-weight:700, word-break:keep-all)
- 중앙 패널: badge(CTA) + 실행 포인트 3가지 (번호 + 한 줄)
- 우 패널: 다음 단계 구체 명령어 or 연락처 (font-family:monospace for commands)"
)

else
# ── 일반 템플릿 ────────────────────────────────────────────────────

slide_patterns=(
  "Pattern C|magazine_split"
  "Pattern A|bento_grid"
  "Pattern A|comparison_table"
  "Pattern C|2분할 (비교/대조)"
  "Pattern A|zigzag_rows"
  "Pattern B|stat_trio"
  "Pattern A|bento_grid"
  "Pattern C|3분할 big_statement"
  "Pattern C|three_split_verdict"
)

slide_sections=(
"### S1 — 타이틀 [Pattern C: magazine_split]
- 주제: ${topic}
- 좌 패널 58%: TODO
- 우 패널 42%: TODO
- AP-08 필수: 패널에 display:flex; flex-direction:column; justify-content:center"
"### S2 — TODO [Pattern A: bento_grid]
- badge: TODO
- 제목: TODO
- 내용: TODO"
"### S3 — TODO [Pattern A: comparison_table]
- badge: TODO
- 제목: TODO
- 표 항목: TODO"
"### S4 — TODO [Pattern C: 2분할 (비교/대조)]
- 좌 패널: TODO
- 우 패널: TODO
- AP-08 필수: 패널에 display:flex; flex-direction:column; justify-content:center"
"### S5 — TODO [Pattern A: zigzag_rows]
- badge: TODO
- 제목: TODO
- 행 구성: TODO"
"### S6 — TODO [Pattern B: stat_trio]
- badge: TODO
- 제목: TODO
- 핵심 수치 3개: TODO"
"### S7 — TODO [Pattern A: bento_grid]
- badge: TODO
- 제목: TODO
- 카드 구성: TODO"
"### S8 — TODO [Pattern C: 3분할 big_statement]
- 좌 패널: TODO
- 중앙 패널: TODO
- 우 패널: TODO
- AP-08 필수: 패널에 display:flex; flex-direction:column; justify-content:center"
"### S9 — TODO [Pattern C: three_split_verdict]
- 좌 패널: TODO
- 중앙 패널: TODO
- 우 패널: TODO
- AP-08 필수: 패널에 display:flex; flex-direction:column; justify-content:center"
)

fi

{
  echo "---"
  echo "# ${topic} 슬라이드 브리프"
  echo "> 자동 생성: gen-brief.sh | 프리셋: ${preset} | ${slide_n}슬라이드"
  echo
  echo "## 색상 시스템 [${preset}]"
  echo '```css'
  cat <<CSS
@page { size: 1280px 720px; margin: 0; }
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: var(--bg); }
.slide { width:1280px; height:720px; overflow:hidden; position:relative; background:var(--bg); font-family:'Pretendard','Apple SD Gothic Neo',sans-serif; }

/* 선택된 프리셋 :root 블록 */
${preset_block}

/* AP-13: 한국어 줄바꿈 */
h1,h2,h3,.title,.headline,.slide-title { word-break:keep-all; overflow-wrap:break-word; }
p,li,.desc,.sub,.card-text,.badge-text { word-break:keep-all; overflow-wrap:break-word; }

/* AP-12: 배지 */
.badge { display:inline-block; width:fit-content; border:1.5px solid var(--accent);
         color:var(--accent); border-radius:6px; padding:4px 12px;
         font-size:11px; letter-spacing:0.08em; font-weight:600; }
CSS

  # Planby 전용 추가 CSS
  if [ "$preset" = "planby_dark" ]; then
    cat <<'CSS'

/* Planby 워터마크 — 모든 슬라이드 공통 */
.slide::after {
  content: "planby";
  position: absolute; bottom: 18px; left: 32px;
  font-size: 10px; font-weight: 700; letter-spacing: 0.10em;
  color: var(--text-muted); z-index: 10;
  font-family: 'Pretendard','Apple SD Gothic Neo',sans-serif;
}

/* Planby 웨이브 장식 (S1 타이틀 전용) */
.planby-wave {
  position: absolute; top: 0; right: 0;
  width: 55%; height: 100%; overflow: hidden; pointer-events: none;
}
.planby-wave svg { width: 100%; height: 100%; }
CSS
  fi

  echo '```'
  echo
  echo "## 레이아웃 배정"
  echo "| 슬라이드 | 패턴 | 레이아웃 |"
  echo "|---------|------|---------|"

  i=1
  while [ "$i" -le "$slide_n" ]; do
    IFS='|' read -r ptn layout <<< "${slide_patterns[$((i-1))]}"
    echo "| S${i} | ${ptn} | ${layout} |"
    i=$((i+1))
  done

  echo
  echo "## 슬라이드별 내용 (TODO: 내용 채울 것)"
  echo

  i=1
  while [ "$i" -le "$slide_n" ]; do
    printf '%s\n\n' "${slide_sections[$((i-1))]}"
    i=$((i+1))
  done

  echo "## 필수 AP 체크 (모든 슬라이드 공통)"
  echo "- AP-08: Pattern C 패널 → display:flex; justify-content:center 필수"
  echo "- AP-11: card-grid → flex:1; min-height:0; align-content:stretch 필수"
  echo "- AP-12: 배지 → display:inline-block 필수"
  echo "- AP-13: 한국어 → word-break:keep-all 전역 필수"
  echo "- AP-16: ghost text → .slide 직계 자식 position:absolute z-index:0"
  echo "- AP-17: 다크 테마 선 → rgba() 사용 필수"
  echo "- AP-20: 카드 내 텍스트 하단 쏠림 방지 → .card { display:flex; flex-direction:column; justify-content:space-between } 제목 상단, 설명 margin-top:auto"
  echo "- AP-21: stat/timeline 카드 중간 공백 방지 → justify-content:flex-start; gap:10px 사용. space-between 금지. margin-top:auto 절대 금지"
  echo

  if [ "$preset" = "planby_dark" ]; then
    echo "## Planby 브랜드 규칙 (planby_dark 전용)"
    echo "- 워터마크: .slide::after { content:'planby' } — CSS에 이미 정의됨. 각 슬라이드 HTML에 별도 추가 불필요"
    echo "- 액센트 색상: #5E5CE6 (인디고 퍼플) 고정 — 임의 변경 금지"
    echo "- S1 우측 패널: .planby-wave SVG 곡선+도트 장식 반드시 포함"
    echo "  SVG 예시: <path d='M0,360 C200,200 400,500 600,300 S900,100 1000,360' stroke='#5E5CE6' stroke-width='2.5' fill='none'/>"
    echo "  도트: <circle> 요소 10~15개, r=3~5, fill='#5E5CE6', opacity=0.6~0.9"
    echo "- 배지 스타일: border-color:#5E5CE6; color:#5E5CE6 (--accent 변수 사용)"
    echo "- 폰트: Pretendard 우선, 없으면 Apple SD Gothic Neo"
    echo "- 타이틀 텍스트: 흰색(#FFFFFF), 서브텍스트: #D1D1DB"
    echo
  fi

  echo "## 생성 완료 후 CHK 자가검증 (필수)"
  echo "bash ~/Desktop/agent-orchestration/scripts/check-slides.sh /tmp/${slug}-brief.html"
  echo "---"
} > "$outfile"

echo "BRIEF: ${outfile}"
echo "PRESET: ${preset}"
echo "SLIDES: ${slide_n}"
