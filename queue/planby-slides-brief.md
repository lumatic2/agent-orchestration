# 슬라이드 생성 브리프 — Planby 컨설팅 성과 보고

## 목표
4주 Planby 컨설팅 프로젝트의 성과를 보여주는 9슬라이드 HTML 덱 생성.
발표자: 컨설턴트(나). 수신자: 포트폴리오 열람자 or 클라이언트.

## 출력
- 파일: `~/Desktop/planby-consulting-result.html`
- 렌더: `bash ~/Desktop/agent-orchestration/scripts/render-slides.sh ~/Desktop/planby-consulting-result.html planby-consulting-result`

## 슬라이드 스펙
- 크기: 1280×720px (height 반드시 fixed, min-height 금지 — AP-04)
- 테마: light (배경 #FFFFFF, 강조 #2563EB)
- 폰트: Inter (Google Fonts)
- 이모지 금지 — SVG 아이콘만 사용 (AP-no-emoji)
- @page { size: 1280px 720px; margin: 0; } 반드시 포함

## 전역 필수 CSS (반드시 포함)
```css
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
/* 슬라이드 고정 (AP-04) */
.slide { width: 1280px; height: 720px; overflow: hidden; position: relative; }
```

---

## S1 — 표지 (Pattern C: title_left_panel)
- 좌측 파란 패널(35%) + 우측 흰 패널(65%)
- 좌 패널: 파란 배경(#2563EB), 흰 텍스트
  - 상단 소제목(13px muted): "Strategy Consulting"
  - 메인 제목(38px bold): "Planby\nManagement\nArchitecture"
  - 하단 날짜/기간(13px): "2026.02 — 2026.03 · 4주"
- 우 패널: 흰 배경
  - 배지: "PROJECT OVERVIEW"
  - 부제(22px bold, #1E293B): "전략·재무·GTM·운영\n통합 경영 구조 완성"
  - 아이콘 리스트 4개 (SVG 아이콘 + 텍스트):
    - 산출물 5개 완성
    - 핵심 수치 전부 확정
    - Decision Framework v1.0
    - 4주 완성
- AP-08: 두 패널 모두 display:flex; flex-direction:column; justify-content:center 필수

---

## S2 — 왜 이 작업이 필요했나 (Pattern A: icon_card_grid, 4카드 1행)
- 배지: "PROBLEM"
- 제목(32px): "구조화 이전의 플랜바이"
- 서브(15px muted): "수치 불명확, 딜 선택 기준 없음, 런웨이 위기"
- 4개 카드 (repeat(4,1fr), 1행):
  1. SVG: alert-circle / "매출 수치 불일치" / "초기 제시 7.8억 → 실제 2.89억 (재무제표 확인)"
  2. SVG: help-circle / "딜 선택 기준 부재" / "경험·직관 의존 → 데이터 기반 기준 필요"
  3. SVG: layers / "운영 캐파 불투명" / "P_parallel 상한 미정, 병렬 가능 건수 불명확"
  4. SVG: trending-down / "런웨이 긴박" / "현금 1.97억, TIPS 5억 입금 전 실질 8개월"
- card-grid: flex:1; min-height:0; align-content:stretch (AP-11)
- Pattern A: body justify-content:center (카드 4개라 높이 충분)

---

## S3 — 확정한 핵심 수치 (Pattern B: stat_trio)
- 배지: "KEY METRICS"
- 제목(32px): "4주간 확정한 수치들"
- 서브(14px): "가정값 → 실데이터 기반 확정값으로"
- 3개 stat 카드 (repeat(3,1fr), flex:1 min-height:0):
  1. 숫자: "60%" / 단위: "Win rate" / 설명: "파이프라인 sizing 근거 ✓"
  2. 숫자: "66.7%" / 단위: "재발주율" / 설명: "9건 중 6건 기존 고객 ✓"
  3. 숫자: "6.0억" / 단위: "Base 매출" / 설명: "실데이터 4,900만 기반 시나리오 ✓"
- trio-num: 64px, #2563EB
- trio-unit: 18px, #94A3B8
- trio-desc: 13px, #94A3B8

---

## S4 — 비즈니스 모델 흐름 (Pattern B: flow_arrows, 5단계)
- 배지: "BUSINESS MODEL"
- 제목(32px): "Custom Engine 딜 흐름"
- 서브(14px): "모든 신규 딜은 PoC → 본계약 단계 적용"
- 5개 flow-box + 4개 화살표 (→):
  1. "인바운드" / "아웃바운드"
  2. "초도 미팅" / "질문 먼저"
  3. "PoC" / "1,500만 · 4~6주"
  4. "본계약" / "평균 4,900만"
  5. "유지보수" / "100만/월"
- flow-box: border-radius:12px; background:#F8FAFC; border:1.5px solid #E2E8F0
- 화살표: SVG arrow-right 아이콘(#2563EB)
- flow-row: flex; align-items:center; justify-content:center; gap:0; flex:1; min-height:0; padding:0 48px

---

## S5 — Revenue Architecture (Pattern C: right_accent_panel)
- 좌측(72%): 흰 배경
  - 배지: "FINANCE"
  - 제목(30px): "매출 구조 — 3 레이어"
  - 3개 레이어 항목(바 형태):
    - Layer 1: "Custom Engine" / "P×회전수×단가. Base: 4,900만×3건×4회전 = 5.88억" / 바 폭 88%
    - Layer 2: "Recurring MRR" / "유지보수 4건×100만/월 = 연 1,200만" / 바 폭 12%
    - Layer 3: "SaaS" / "2026 역할: 커스텀 리드 채널 (직접 매출 제한적)" / 바 폭 5%
  - 바 배경: #EFF6FF, 바 fill: #2563EB
- 우측 패널(28%): 파란 배경(#2563EB)
  - 히어로 숫자(72px, 흰): "6.0억"
  - 라벨(14px, #BFDBFE): "Base 시나리오"
  - 서브 수치들(13px, #BFDBFE):
    - "KPI: 9.72억"
    - "Gross: 3.0억 (50%)"
    - "Operating: 1.5억 (25%)"
- AP-08: 두 패널 모두 display:flex; flex-direction:column; justify-content:center 필수
- 우측 패널 내부에 align-items:center도 추가

---

## S6 — 5개 산출물 (Pattern A: icon_card_grid, 6카드 3×2)
- 배지: "DELIVERABLES"
- 제목(32px): "4주 동안 만든 것들"
- 서브(14px): "Management Architecture v1.0 — 5개 도메인 통합"
- 6개 카드 (repeat(3,1fr), 2행, flex:1 min-height:0 align-content:stretch) — AP-15:
  1. SVG: bar-chart-2 / "Finance" / "Revenue Architecture · Base 6억 시나리오 확정"
  2. SVG: target / "GTM" / "3개 세그먼트 · Win rate 60% · 재발주율 66.7%"
  3. SVG: settings / "Operations" / "딜 흐름 · 병렬 캐파(P=3) · 스쿼드 4개"
  4. SVG: check-square / "Decision Framework" / "Fail-fast 2조건 · 가중 채점 32.5pt"
  5. SVG: book-open / "Architecture v1.0" / "5도메인 통합본 · 확정 수치 전체 반영"
  6. SVG: clipboard / "운영 매뉴얼" / "Win rate · 재발주 LTV · PoC 전환율 측정 기준"

---

## S7 — Decision Framework (Pattern B: asymmetric_panel)
- 배지: "FRAMEWORK"
- 제목(32px): "딜 선택 기준 — Decision Framework v1.0"
- 서브(14px): "슬롯 1개가 3개월을 잠근다 — 데이터 기반 판단 구조 설계"
- 좌측(45%): 히어로 영역
  - 큰 숫자(56px, #2563EB): "32.5"
  - 라벨(14px): "가중 채점 만점"
  - 구분선
  - 판정 기준 3단계:
    - "25pt+ → Go"
    - "18~25pt → Conditional"
    - "18pt 미만 → No"
- 수직 구분선(1px solid #E2E8F0)
- 우측(55%): 번호 리스트 (01/02/03/04):
  1. "Fail-fast 1 (F1)" / "리소스 초과 — 개발기간 6개월+ 또는 PM 전담 필요 시"
  2. "Fail-fast 2 (F2)" / "도메인 외 — 건축·건설·부동산 외 커스텀 수주"
  3. "가중 채점" / "규모·재발주·전략성·레퍼런스·확산성 5개 기준"
  4. "동점 우선순위" / "재발주·확산 > 계약 규모 > 레퍼런스"
- content-fill: flex:1; min-height:0 (AP-03)

---

## S8 — 핵심 메시지 (Pattern C: big_statement_white)
- 배경: 흰색
- ghost 텍스트(position:absolute z-index:0, opacity:0.04, font-size:140px, #1E293B): "STRUCTURE"
- 배지 영역: 좌상단 구분선(——) + "INSIGHT"
- 3줄 타이포 계층:
  - 줄1(18px, #94A3B8): "4주간의 작업이 증명한 것"
  - 줄2(44px bold, #2563EB): "더 정확한 구조를 보면"
  - 줄3(44px bold, #1E293B): "더 좋은 결정을 내린다"
- 하단 서브(15px, #94A3B8): "Planby Management Architecture v1.0 · 2026-03-06 확정"
- AP-16: ghost는 반드시 .slide 직계 자식, position:absolute, z-index:0

---

## S9 — 다음 단계 (Pattern C: three_split_verdict)
- 3분할: 좌(흰, 33%) + 중(파란 #2563EB, 34%) + 우(흰, 33%)
- 좌 패널:
  - 소제목(12px letter-spacing, #94A3B8): "IMMEDIATE"
  - 제목(22px bold, #1E293B): "즉각 액션"
  - 리스트(13px):
    - "Series A 프로세스 착수"
    - "VC 미팅 재개"
    - "IR 덱 수치 최신화"
    - "삼성E&A 2차 클로징"
- 중앙 패널 (파란 배경):
  - 소제목(12px, #BFDBFE): "2026 THEME"
  - 핵심 문구(28px bold, 흰): "Custom\nEngine\nYear"
  - 하단 설명(13px, #BFDBFE): "수주·납품 역량\n수치로 증명"
- 우 패널:
  - 소제목(12px, #94A3B8): "ONGOING"
  - 제목(22px bold, #1E293B): "운영 기준"
  - 리스트(13px):
    - "Decision Framework 채점 의무화"
    - "N_maint 분기별 점검"
    - "Win rate 반기별 갱신"
    - "파이프라인 구조 유지"
- AP-08: 3개 패널 모두 display:flex; flex-direction:column; justify-content:center 필수 (패딩 최소 52px)

---

## Anti-pattern 필수 준수
- AP-01: flex child height:100% 금지
- AP-03: center body 안 flex:1 공존 금지
- AP-04: height:720px fixed (min-height 금지)
- AP-08: Pattern C 패널 전부 flex centering (패딩 ≥52px)
- AP-09: margin-top:auto 금지
- AP-10: 콘텐츠 짧으면 justify-content:flex-start + padding-top:80px
- AP-11: card-grid에 flex:1; min-height:0; align-content:stretch
- AP-12: 배지 display:inline-block
- AP-13: 전역 word-break:keep-all
- AP-15: 6카드 → 3열
- AP-16: ghost text position:absolute z-index:0 (.body 바깥)

## 완료 후 검증 (CHK 목록)
CHK-01: height:720px 존재 확인
CHK-02: justify-content:center 출현 수 ≥ Pattern C 패널 수
CHK-03: align-content:stretch 카드 슬라이드마다 존재
CHK-04: display:inline-block 배지에 적용
CHK-05: word-break:keep-all 전역 CSS
CHK-06: height:100% flex child 없음
