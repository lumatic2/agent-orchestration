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

  if [[ "$t" == *"커피"* || "$t" == *"카페"* || "$t" == *"원두"* || "$t" == *"브루잉"* || "$t" == *"바리스타"* ]]; then
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
  echo
  echo "## 생성 완료 후 CHK 자가검증 (필수)"
  echo "bash ~/Desktop/agent-orchestration/scripts/check-slides.sh /tmp/${slug}-brief.html"
  echo "---"
} > "$outfile"

echo "BRIEF: ${outfile}"
echo "PRESET: ${preset}"
echo "SLIDES: ${slide_n}"
