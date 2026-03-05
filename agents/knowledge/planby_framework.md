# [KNOWLEDGE] Planby — 사업전략·재무 프레임워크

## Planby 개요
Business Strategy & Finance 플랫폼. OKR-ROI 구조 연결이 핵심.

---

## 전략-재무 연결 프레임워크

### Strategy → Finance 연결 흐름
```
전략 목표 (Objective)
  ↓
핵심 결과 (Key Results) — 수치화
  ↓
재무 KPI (매출, 이익, 현금)
  ↓
재무모델 (P&L, Cash Flow, Balance Sheet)
  ↓
기업가치 (EV/DCF/Multiple)
```

### 전략 레이어별 재무 연결
| 전략 레이어 | 프레임워크 | 연결 재무지표 |
|---|---|---|
| 비전/미션 | BSC 학습·성장 | 인당 매출, R&D 투자율 |
| 사업전략 | Porter 5Forces | 영업이익률, 시장점유율 |
| 성장전략 | Ansoff Matrix | 매출성장률, CAGR |
| 운영전략 | OKR | EBITDA, FCF |
| 재무전략 | DCF, EVA | ROIC, EV |

---

## OKR-재무 설계 원칙

### 연간 재무 OKR 예시 (B2B SaaS)
```
Objective: 지속가능한 수익 성장 기반 구축

KR1: ARR 5억 → 8억 달성 (YoY +60%)
KR2: NRR 105% 이상 유지
KR3: Gross Margin 70% 이상 달성
KR4: CAC Payback Period 18개월 이하 달성
KR5: 분기 FCF 흑자 전환
```

### OKR-KPI 위계
```
연간 OKR (CEO/CFO 레벨)
  └─ 분기 OKR (팀 레벨)
       └─ 월간 KPI (실행 레벨)
            └─ 주간 지표 (운영 레벨)
```

---

## 재무 시나리오 분석 (Planning)

### 3-Scenario 모델
| 시나리오 | 가정 | 용도 |
|---|---|---|
| Base | 현실적 전망 | 경영계획, 예산 |
| Upside | 긍정적 (+20~30%) | 투자유치 IR |
| Downside | 보수적 (-20~30%) | 리스크 관리 |

### 민감도 분석 핵심 변수 (SaaS)
1. 신규 고객 획득 수 (가장 영향 큼)
2. 평균계약가치 (ACV)
3. Churn Rate
4. Gross Margin
5. 영업/마케팅 효율 (CAC)

---

## M&A·투자 의사결정 체크리스트

### 인수 타당성 분석 (Buy-side)
```
□ 전략적 fit (시장, 기술, 인재)
□ 재무 모델링 (DCF + Multiple)
□ Synergy 분석 (매출 시너지 vs 비용 절감)
□ Integration cost 추정
□ 거래 구조 (주식 vs 자산 인수, 세무 영향)
□ Due Diligence (재무, 법무, 기술)
□ 자금조달 계획 (LBO 구조 포함)
```

### LBO (Leveraged Buyout) 기초
```
인수자금 = Equity (30~40%) + Debt (60~70%)

수익 = EBITDA 성장 + Multiple Expansion + 부채 상환
IRR목표 = 20~25% (PE 펀드 기준)

Entry Multiple × 투자기간 후 Exit Multiple = 투자배수(MOIC)
```

---

## 스타트업 → 중견기업 재무 성숙도 단계

### Stage 1: 생존기 (0~3년)
- 핵심 지표: Runway, MoM 성장률, Unit Economics
- 재무관리: 현금흐름 주간 모니터링
- 회계: 세금계산서 적시 발행, 원천징수 이행

### Stage 2: 성장기 (Series A~B)
- 핵심 지표: ARR, NRR, CAC Payback
- 재무관리: 월간 P&L 리뷰, 예산 vs 실적 분석
- 회계: 월결산 체계화, ERP 도입 시작

### Stage 3: 확장기 (Series C~Pre-IPO)
- 핵심 지표: EBITDA, FCF, Rule of 40
- 재무관리: 분기 Board 보고, 3-way 재무모델
- 회계: K-IFRS 적용 준비, 내부통제 강화

### Stage 4: 성숙기 (IPO 이후)
- 핵심 지표: EPS, ROE, DPS
- 재무관리: IR, 공시 의무, 배당 정책
- 회계: 감사인 주기적 지정, 내부회계관리 인증

---

## 재무모델 3-Statement Model

### 연결 구조
```
손익계산서 (P&L)
  → 순이익 → 이익잉여금 (BS)
  → D&A → 영업CF 조정 (CF)

현금흐름표 (CF)
  → 기말 현금 → 유동자산 (BS)

대차대조표 (BS)
  → 차기 기초 잔액 → P&L 시작값
```

### SaaS 재무모델 핵심 드라이버
```
MRR_t = MRR_{t-1} + New MRR + Expansion MRR - Churned MRR

New MRR = 신규 고객 수 × ARPU
Expansion MRR = 기존 고객 Upsell
Churned MRR = 기초 MRR × Churn Rate
```

---

## Planby에서 자주 나오는 회계 이슈

### 수익 인식 (IFRS 15 실무)
- SaaS 구독: 기간에 걸쳐 인식 (선수수익으로 이연)
- 구현비 (Implementation Fee): 별도 수행의무 여부 판단
- 약정기간 할인: 변동대가 추정

### 재고자산 (제조업)
- 원가 = 직접재료비 + 직접노무비 + 제조간접비
- 저가법 (LCM): 원가 vs 순실현가능가치 중 낮은 쪽
- FIFO vs 평균법 (K-IFRS: LIFO 금지)

### 개발비 자산화 (IFRS 38)
```
연구단계: 비용처리 (자산화 금지)
개발단계: 6가지 요건 모두 충족 시 자산화
  ① 기술적 실현가능성 ② 완성 의도 ③ 사용·판매 능력
  ④ 미래 경제적 효익 ⑤ 자원 충분 ⑥ 지출 신뢰성 있게 측정
```
