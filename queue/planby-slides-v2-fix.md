# Planby 슬라이드 v2 — 레이아웃 픽스 브리프

## 목표
`~/Desktop/planby-consulting-result.html` 재생성 (v2).
이전 버전의 수직 정렬 문제 전체 수정.
렌더: `bash ~/Desktop/agent-orchestration/scripts/render-slides.sh ~/Desktop/planby-consulting-result.html planby-consulting-result`

## 콘텐츠
콘텐츠는 이전 버전과 동일 (변경 없음). 레이아웃·CSS만 수정.

---

## 핵심 문제: 수직 정렬 실패

### 루트 원인
- Pattern C 패널들: `justify-content: center` 미적용
- 카드 내부: 콘텐츠가 `flex-start` 쏠림 (justify-content 누락)
- Pattern A `.body`: 카드 그리드가 `flex-start`로 정렬됨
- S8 big statement: 슬라이드 전체 세로 중앙 정렬 미적용

---

## 전역 CSS 필수 (원본 + 추가)

```css
/* 원본 유지 */
@page { size: 1280px 720px; margin: 0; }
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'Inter', sans-serif; }
.slide { width: 1280px; height: 720px; overflow: hidden; position: relative; }

/* 한국어 word-break (AP-13) */
h1, h2, h3, .title, .headline, .slide-title {
  word-break: keep-all; overflow-wrap: break-word; text-wrap: balance;
}
p, li, .desc, .sub, .card-text {
  word-break: keep-all; overflow-wrap: break-word;
}

/* 배지 (AP-12) */
.badge {
  display: inline-block; width: fit-content;
  border: 1.5px solid #2563EB; border-radius: 6px;
  padding: 4px 12px; font-size: 11px; letter-spacing: 0.08em; color: #2563EB;
}

/* [FIX] Pattern C 패널 공통 — AP-08 */
.panel {
  display: flex;
  flex-direction: column;
  justify-content: center;  /* 반드시 center */
}

/* [FIX] 카드 내부 레이아웃 */
.card {
  display: flex;
  flex-direction: column;
  justify-content: flex-start;
  padding: 32px 28px;
  border-radius: 12px;
  background: #F8FAFC;
  border: 1.5px solid #E2E8F0;
}

/* [FIX] card-grid — AP-11 */
.card-grid {
  display: grid;
  flex: 1;
  min-height: 0;
  align-content: stretch;
  gap: 16px;
}

/* [FIX] slide header (배지+제목+서브) */
.slide-header {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 64px 80px 24px;
  flex-shrink: 0;
}

/* [FIX] slide body */
.slide-body {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
  padding: 0 80px 48px;
}
```

---

## 슬라이드별 필수 수정사항

### S1 — 표지 (Pattern C: 좌35% + 우65%)

```css
.s1-left {
  width: 35%; height: 720px;
  background: #2563EB;
  display: flex; flex-direction: column; justify-content: center;
  padding: 64px 52px;
}
.s1-right {
  width: 65%; height: 720px;
  background: #FFFFFF;
  display: flex; flex-direction: column; justify-content: center;  /* [FIX] */
  padding: 64px 72px;
}
```

### S2 — 문제 (Pattern A: 4카드 1행)

```css
.s2 .slide { display: flex; flex-direction: column; }
.s2 .slide-header { flex-shrink: 0; }
.s2 .slide-body { flex: 1; min-height: 0; display: flex; flex-direction: column; }
.s2 .card-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 16px;
  flex: 1; min-height: 0;
  align-content: stretch;
}
/* 카드 내부: 콘텐츠 상단 정렬 + 넉넉한 패딩 */
.s2 .card {
  display: flex; flex-direction: column; gap: 10px;
  padding: 36px 28px;
  justify-content: flex-start;
}
```

### S3 — 핵심 수치 (Pattern B: stat_trio)

```css
.s3 .slide { display: flex; flex-direction: column; }
.s3 .card-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 20px;
  flex: 1; min-height: 0;
  align-content: stretch;
}
/* stat 카드 내부: 수직 중앙 정렬 */
.s3 .card {
  display: flex; flex-direction: column;
  justify-content: center;   /* [FIX] center */
  align-items: flex-start;
  padding: 48px 40px;
  gap: 8px;
}
.trio-num { font-size: 64px; font-weight: 700; color: #2563EB; line-height: 1; }
.trio-unit { font-size: 18px; color: #94A3B8; }
.trio-desc { font-size: 13px; color: #94A3B8; }
```

### S4 — Business Model Flow (Pattern B: flow_arrows)

```css
.s4 .slide { display: flex; flex-direction: column; }
.s4 .slide-body {
  flex: 1; min-height: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;   /* [FIX] flow 세로 중앙 */
}
.flow-row {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  gap: 0;
  padding: 0 60px;
}
.flow-box {
  flex: 1;
  display: flex; flex-direction: column;
  justify-content: center; align-items: center;
  gap: 8px;
  padding: 28px 16px;
  min-height: 120px; max-height: 160px;  /* [FIX] 적당한 높이 */
  border-radius: 12px;
  background: #F8FAFC; border: 1.5px solid #E2E8F0;
  text-align: center;
}
.flow-arrow {
  flex-shrink: 0;
  width: 40px;
  display: flex; align-items: center; justify-content: center;
}
```

### S5 — Revenue Architecture (Pattern C: 좌72% + 우28%)

```css
.s5-left {
  width: 72%; height: 720px;
  background: #FFFFFF;
  display: flex; flex-direction: column; justify-content: center;  /* [FIX] */
  padding: 64px 72px;
}
.s5-right {
  width: 28%; height: 720px;
  background: #2563EB;
  display: flex; flex-direction: column;
  justify-content: center; align-items: center;
  padding: 52px 40px;
  text-align: center;
}
```

### S6 — 산출물 (Pattern A: 6카드 3×2)

```css
.s6 .card-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  grid-template-rows: repeat(2, 1fr);
  gap: 16px;
  flex: 1; min-height: 0;
  align-content: stretch;
}
.s6 .card {
  display: flex; flex-direction: column; gap: 8px;
  justify-content: flex-start;
  padding: 28px 28px;
}
```

### S7 — Decision Framework (Pattern B: asymmetric)

```css
.s7 .slide { display: flex; flex-direction: column; }
.s7 .content-row {
  display: flex; flex-direction: row;
  flex: 1; min-height: 0;
  gap: 0;
  padding: 0 80px 48px;
}
/* 좌 히어로 */
.s7 .hero-left {
  width: 45%;
  display: flex; flex-direction: column;
  justify-content: center;   /* [FIX] center */
  padding: 40px 48px 40px 0;
  border-right: 1px solid #E2E8F0;
}
/* 우 번호 리스트 */
.s7 .list-right {
  width: 55%;
  display: flex; flex-direction: column;
  justify-content: center;   /* [FIX] center */
  gap: 12px;
  padding: 40px 0 40px 48px;
}
```

### S8 — 핵심 메시지 (Pattern C: big_statement_white)

```css
.s8 .slide {
  display: flex; flex-direction: column;
  justify-content: center;   /* [FIX] 슬라이드 전체 세로 중앙 */
  padding: 0 120px;
}
/* ghost text — AP-16 */
.s8 .ghost {
  position: absolute; z-index: 0;
  font-size: 140px; font-weight: 800;
  color: #1E293B; opacity: 0.04;
  bottom: 60px; right: -20px;
  pointer-events: none; user-select: none;
  white-space: nowrap;
}
.s8 .content {
  position: relative; z-index: 1;
}
```

### S9 — 다음 단계 (Pattern C: three_split)

```css
.s9 .slide { display: flex; flex-direction: row; }
.s9 .panel-left {
  width: 33%; height: 720px;
  background: #FFFFFF;
  display: flex; flex-direction: column; justify-content: center;  /* [FIX] */
  padding: 52px;
}
.s9 .panel-center {
  width: 34%; height: 720px;
  background: #2563EB;
  display: flex; flex-direction: column;
  justify-content: center; align-items: center;
  padding: 52px 40px; text-align: center;
}
.s9 .panel-right {
  width: 33%; height: 720px;
  background: #FFFFFF;
  display: flex; flex-direction: column; justify-content: center;  /* [FIX] */
  padding: 52px;
}
```

---

## Anti-pattern 준수
- AP-01: flex child height:100% 금지
- AP-03: center body 안 flex:1 공존 금지
- AP-04: height:720px fixed (min-height 금지)
- AP-08: Pattern C 패널 전부 justify-content:center (패딩 ≥52px)
- AP-09: margin-top:auto 금지
- AP-11: card-grid flex:1; min-height:0; align-content:stretch
- AP-12: 배지 display:inline-block
- AP-13: 전역 word-break:keep-all
- AP-15: 6카드 → 3열
- AP-16: ghost text position:absolute z-index:0 (.slide 직계 자식)

## 완료 후 검증
CHK-01: height:720px 존재
CHK-02: justify-content:center ≥ Pattern C 패널 수 (S1×2, S5×2, S8×1, S9×3 = 최소 8개)
CHK-03: align-content:stretch 카드 슬라이드마다
CHK-04: display:inline-block 배지
CHK-05: word-break:keep-all 전역
CHK-06: height:100% flex child 없음

## 콘텐츠 (변경 없음)
원본 브리프 참조: `~/Desktop/agent-orchestration/queue/planby-slides-brief.md`
