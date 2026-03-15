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
  elif [[ "$t" == *"여행"* || "$t" == *"음식"* || "$t" == *"요리"* || "$t" == *"라이프스타일"* || "$t" == *"관광"* ]]; then
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
  --accent-text:#A8A6FF;  /* 다크 카드 위 텍스트용 — 대비비 5.1:1 */
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
  "Pattern C|2분할"
  "Pattern A|comparison_table"
  "Pattern A|zigzag_rows"
  "Pattern B|stat_trio"
  "Pattern A|timeline_flow"
  "Pattern C|3분할 big_statement"
  "Pattern C|three_split_verdict"
)

slide_sections=(
"### S1 — 타이틀 [magazine_split]
- 주제: ${topic}
- 좌 60%: 배지(PLANBY) + 주제 대형 타이틀 + 부제 1줄 + 날짜/버전
- 우 40%: planby-wave 클래스 SVG 장식 (곡선 2~3줄 + 도트 10개, stroke:#5E5CE6)"
"### S2 — TODO [bento_grid]
- badge: 현황 분석
- 제목: TODO
- 카드 3~4개: 각 카드에 라벨(소형, muted) + 핵심 수치(대형, accent-text) + 설명 2~3줄"
"### S3 — TODO [2분할]
- badge: 핵심 비교
- 제목: TODO
- 좌 50%: 핵심 주장 3~4포인트
- 우 50%: 수치 비교 or 카드 그리드"
"### S4 — TODO [comparison_table]
- badge: 기능 구성
- 제목: TODO
- 표: 4행 × 3열 (항목 | Before | After)"
"### S5 — TODO [zigzag_rows]
- badge: 실행 흐름
- 제목: TODO
- 3단계: 각 행 = 번호 원형 + 단계명 + 설명 1~2줄"
"### S6 — TODO [stat_trio]
- badge: 운영 지표
- 제목: TODO
- 수치 3개: 각 카드에 대형 숫자 + 단위 + 라벨 + 설명 2~3줄"
"### S7 — TODO [timeline_flow]
- badge: 로드맵
- 제목: TODO
- 4단계: 각 카드에 날짜 + 단계명 + 설명 3~4줄 (구체적 수치·액션 포함)"
"### S8 — TODO [3분할 big_statement]
- badge: 핵심 메시지
- 좌 30%: 핵심 메시지 대형 1~2문장
- 중 40%: 근거 리스트 or 주요 수치
- 우 30%: 요약 포인트 번호 목록"
"### S9 — TODO [three_split_verdict]
- 좌 33%: 결론 1문장 대형
- 중 34%: badge(CTA) + 실행 포인트 3가지
- 우 33%: 다음 단계 명령 or 연락처"
)

else
# ── 일반 템플릿 ────────────────────────────────────────────────────

slide_patterns=(
  "Pattern C|magazine_split"
  "Pattern A|bento_grid"
  "Pattern A|comparison_table"
  "Pattern C|2분할"
  "Pattern A|zigzag_rows"
  "Pattern B|stat_trio"
  "Pattern A|bento_grid"
  "Pattern C|3분할 big_statement"
  "Pattern C|three_split_verdict"
)

slide_sections=(
"### S1 — 타이틀 [magazine_split]
- 주제: ${topic}
- 좌 58%: 배지 + 주제 대형 타이틀 + 부제 1줄
- 우 42%: 주제와 어울리는 시각 요소 (아이콘, 도형, 패턴)"
"### S2 — TODO [bento_grid]
- badge: TODO
- 제목: TODO
- 카드 3~4개: 각 카드에 라벨 + 핵심 수치/키워드 + 설명 2~3줄"
"### S3 — TODO [comparison_table]
- badge: TODO
- 제목: TODO
- 표: 3~4행 × 3열 비교"
"### S4 — TODO [2분할]
- badge: TODO
- 제목: TODO
- 좌 패널: 핵심 주장 + 포인트 목록
- 우 패널: 수치 or 대비 항목"
"### S5 — TODO [zigzag_rows]
- badge: TODO
- 제목: TODO
- 3단계 흐름: 번호 + 단계명 + 설명"
"### S6 — TODO [stat_trio]
- badge: TODO
- 제목: TODO
- 수치 3개: 대형 숫자 + 라벨 + 설명 2~3줄"
"### S7 — TODO [bento_grid]
- badge: TODO
- 제목: TODO
- 카드 3~4개: 각 카드에 제목 + 내용"
"### S8 — TODO [3분할 big_statement]
- 좌 패널: 핵심 메시지 대형
- 중앙 패널: 근거 리스트
- 우 패널: 요약 포인트"
"### S9 — TODO [three_split_verdict]
- 좌 패널: 결론 1문장 대형
- 중앙 패널: 실행 포인트 3가지
- 우 패널: 다음 단계"
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

/* AP-22: ghost/배경 대형 텍스트 — opacity 필수 제한 */
.ghost-bg, .slide-ghost, [class*="ghost"] {
  position:absolute; pointer-events:none; z-index:0; user-select:none;
  opacity:0.05; color:var(--text); font-weight:900; letter-spacing:-0.02em; line-height:1;
}
CSS

  # Planby 전용 추가 CSS
  if [ "$preset" = "planby_dark" ]; then
    cat <<'CSS'

/* Planby 다크 테마 — 텍스트용 accent 오버라이드 (AP-22 대비 확보) */
/* var(--accent)는 장식/fill 전용, 텍스트에는 반드시 var(--accent-text) 사용 */
.badge { color:var(--accent-text); border-color:var(--accent-text); }
.b-value { color:var(--accent-text); }
.stat-number { color:#FFFFFF; }
.tl-date { color:var(--accent-text); font-size:11px; font-weight:600; letter-spacing:0.05em; }

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

  echo "## 디자인 원칙"
  echo "- 카드: flex-direction:column + gap:12px. 요소는 위→아래 순서로 배치. height:100% 채울 것"
  echo "- 패널(2분할·3분할): 각 패널 justify-content:center로 세로 중앙 정렬"
  echo "- 수치 강조: 숫자 크게(48~72px) + 라벨 작게(11~14px) + 설명(12px) 순서로 쌓기"
  echo "- 배경 ghost 텍스트: position:absolute, opacity:0.05 이하, 콘텐츠 flow 밖에 배치"
  echo "- 슬라이드 내용은 주제 [${topic}]에만 집중. 시스템·도구 설명 포함 금지"
  echo

  if [ "$preset" = "planby_dark" ]; then
    echo "## Planby 브랜드"
    echo "- 배경 색: #2C2C2E, 카드: #3C3C3E, 액센트: #5E5CE6 (장식/fill), 텍스트 강조: #A8A6FF"
    echo "- S1 우측: .planby-wave SVG (곡선 path + circle 도트, stroke:#5E5CE6)"
    echo "- 워터마크 'planby'는 CSS ::after로 자동 추가됨 — HTML에 별도 추가 불필요"
    echo
  fi

  echo "## 저장 경로"
  echo "/tmp/${slug}.html 에 전체 슬라이드 저장"
  echo "---"
} > "$outfile"

echo "BRIEF: ${outfile}"
echo "PRESET: ${preset}"
echo "SLIDES: ${slide_n}"
