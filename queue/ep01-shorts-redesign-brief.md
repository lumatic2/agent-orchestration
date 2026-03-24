ep01-ai-time-shorts 슬라이드 5개를 레퍼런스 기반으로 리디자인해줘.

## 대상 파일
C:/Users/1/Desktop/유튜브영상/src/videos/ep01-ai-time-shorts/
Slide1.tsx ~ Slide5.tsx (5개 파일만 수정, slides.ts/Component.tsx 수정 금지)

## 레퍼런스에서 추출한 디자인 패턴

### 패턴 1: 단어 분리 kinetic 애니메이션
텍스트를 단어 단위로 split하여 각 단어를 span으로 감싸고,
각 단어에 stagger spring (index * 4~6프레임 delay)으로
translateY(40→0) + opacity(0→1) + scale(0.85→1) 조합 적용.

### 패턴 2: clip-path reveal
clipPath로 요소를 드러내는 효과.
inset(100% 0 0 0) → inset(0% 0 0 0) 방향으로 interpolate.

### 패턴 3: 강한 색상 블록 배경
accentColor 배경에 흰 텍스트.
그라디언트: linear-gradient(135deg, accentColor, #1d4ed8)

### 패턴 4: 숫자 bounce scale
번호에 scale(0→1.2→1) bounce:
config: { damping: 120, stiffness: 200, mass: 0.7 }

### 패턴 5: 카드 flip-in
rotateX(12→0deg) + translateY(30→0) + opacity.
카드 wrapper에 perspective: '600px' 적용.

## 슬라이드별 적용 계획

### Slide1 (타이틀)
- 배경: linear-gradient(135deg, accentColor, #1d4ed8), 텍스트 흰색
- '퇴근 후 2시간을' 단어별 split 애니메이션 (패턴1)
- 'AI가 만들어 줍니다' clip-path reveal (패턴2)
- 'AI x 시간' 레이블: letterSpacing 0.05em → 0.2em interpolate

### Slide2 (4개 카드)
- 카드 입장: rotateX flip-in (패턴5)
- 왼쪽 accent bar height(0% → 100%) 애니메이션
- 헤딩 'AI가 대신합니다': clip-path reveal

### Slide3 (번호 리스트)
- 번호(01/02/03): scale bounce (패턴4)
- 텍스트: 기존 translateX 유지, 번호 애니메이션 이후 delay

### Slide4 (나를 위한 투자)
- 배경: accentColor 10% opacity → 20%로 강화
- 카드: scale(0.88→1) + boxShadow 강화
- 인용구: clip-path reveal

### Slide5 (CTA)
- 기존 accentColor 배경 유지
- '나는 이렇게 삽니다' 단어별 split 애니메이션 (패턴1)
- 해시태그 3개 순차 opacity fade (index * 8프레임 delay)

## 공통 규칙
- 1080x1920 기준, padding 80px 유지
- theme.ts 값 사용, ThemeContext accentColor 사용
- spring + interpolate 필수
- wordBreak: keep-all 유지
- fontVariationSettings: wght 900 (WantedSans Variable 굵기 명시)
- 흰 텍스트 사용 시 color: #FFFFFF 명시

## 검증
npx tsc --noEmit 통과 확인 후 결과 보고
