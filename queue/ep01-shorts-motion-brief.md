# ep01-ai-time-shorts 모션 그래픽 추가

## 대상 파일
C:/Users/1/Desktop/유튜브영상/src/videos/ep01-ai-time-shorts/
- Slide1.tsx ~ Slide5.tsx (5개 파일만 수정)
- slides.ts / Component.tsx 수정 금지

## 공통 규칙
- 1080×1920 기준, 기존 레이아웃 유지
- 새 요소는 기존 애니메이션 위에 레이어로 추가
- spring + interpolate 사용
- theme.ts 값, ThemeContext accentColor 사용
- fontVariationSettings: "'wght' 900" 유지
- TypeScript 오류 없도록 타입 명시

---

## Slide1 추가 요소

### 1. 크로마틱 어버레이션 (제목 텍스트)
'퇴근 후 2시간을' 단어 split 텍스트 위에 RGB 레이어 3개 겹치기:
- Red 레이어: translateX(-3px), opacity 0.4, color: '#FF0000', position: absolute
- Blue 레이어: translateX(+3px), opacity 0.4, color: '#0000FF', position: absolute
- 본 텍스트: color: '#FFFFFF', position: relative, zIndex: 1
- frame 기반 oscillation: Math.sin(frame * 0.15) * 2 로 translateX를 미세하게 흔들기

### 2. 배경 컬러 블록 슬라이드인
배경 위에 반투명 컬러 블록 3개:
- 블록A: width 200px, height 100%, accentColor opacity 0.15, left: '-200px' → '0px' (frame 0~15 spring)
- 블록B: width 120px, height 100%, '#1d4ed8' opacity 0.10, right: '-120px' → '0px' (frame 5~20 spring)
- 블록C: width 80px, height 100%, accentColor opacity 0.08, left: 30px, frame 8~23 spring translateX(-80→0)
- 블록들은 AbsoluteFill 내 최하단 레이어 (zIndex: 0)

---

## Slide2 추가 요소

### SVG 체크마크 드로잉 (카드별)
4개 카드 각각 우측 상단 모서리에 SVG 체크마크:
- viewBox="0 0 24 24", width/height: 28px
- path: "M4 12 L9 17 L20 7" (체크 모양)
- stroke: accentColor, strokeWidth: 2.5, fill: none
- strokeDasharray: 30, strokeDashoffset: 30 → 0 (interpolate, frame: cardDelay + 15 ~ cardDelay + 35)
- cardDelay: index * 8 프레임 (카드 flip-in과 동기화)

---

## Slide3 추가 요소

### SVG 수직 연결선 드로잉
01 → 02 → 03 번호 사이를 잇는 세로 점선:
- SVG: position absolute, left: 54px (번호 중앙), top: 첫번째 아이템 하단 ~ 세번째 아이템 상단
- line: x1=12, y1=0, x2=12, y2=전체높이 (실제 아이템 간격에 맞게)
- stroke: accentColor, strokeWidth: 2, strokeDasharray: "6 6"
- strokeDashoffset: 전체길이 → 0 (interpolate, frame 10~40)
- 선이 점차 그려지며 연결되는 효과

---

## Slide4 추가 요소

### 대각선 와이프 배경
배경 위, 카드 아래 레이어:
- 대각선 그라디언트 블록: position absolute, 전체 화면
- background: `linear-gradient(135deg, ${accentColor}08 0%, transparent 60%)`
- frame 0~20 spring으로 opacity 0 → 1
- 추가로 우하단에 큰 원형 글로우:
  width: 600px, height: 600px, borderRadius: '50%'
  background: `radial-gradient(circle, ${accentColor}12 0%, transparent 70%)`
  position: absolute, right: -200px, bottom: -200px
  frame 0~25 spring scale(0→1)

---

## Slide5 추가 요소

### 파티클 버스트 (흰 점들)
중앙에서 방사형으로 퍼지는 흰 점 12개:
- 각 파티클: width/height 8px, borderRadius '50%', background '#FFFFFF', position: absolute
- 각도: (i / 12) * 2 * Math.PI (균등 분포)
- 거리: frame 기반 spring으로 0 → 180px (i * 2프레임 delay로 stagger)
- opacity: frame 10 이후 서서히 fade out (interpolate frame 20~45 → 1→0)
- center: top: '50%', left: '50%' 기준으로 transform 계산
- zIndex: 0 (텍스트 뒤)

### 배경 펄싱 원
배경에 accentColor 원 2개가 pulse:
- 원1: width/height: 300px, borderRadius '50%', border: `2px solid ${accentColor}`, opacity 0.3
  center 기준, scale: 1 + Math.sin(frame * 0.08) * 0.05
- 원2: width/height: 500px, same style, opacity 0.15, phase offset: Math.sin(frame * 0.08 + 1) * 0.05
- 두 원 모두 frame 0~15 spring으로 초기 등장 (scale 0→1)

---

## 검증
작업 완료 후 npx tsc --noEmit 실행하여 타입 오류 없음 확인 후 결과 보고.
