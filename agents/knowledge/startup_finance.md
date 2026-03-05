# [KNOWLEDGE] 스타트업·벤처 재무 핵심

## 투자 단계별 구조

| 단계 | 투자자 | 규모 | 핵심 지표 |
|---|---|---|---|
| Pre-Seed | 창업자·엔젤 | ~5억 | 팀, 아이디어 |
| Seed | 엔젤·초기VC | 5~30억 | MVP, 초기 고객 |
| Series A | VC | 30~150억 | PMF, 초기 매출 |
| Series B | VC·CVC | 150~500억 | 성장 가속 |
| Series C+ | 대형VC·PE | 500억+ | 수익성·확장성 |
| IPO / M&A | 공개시장·전략적 | — | 규모·수익성 |

---

## 핵심 스타트업 지표

### SaaS / 구독 모델
```
ARR (Annual Recurring Revenue) = MRR × 12
MRR (Monthly Recurring Revenue) = 월 반복 매출

NRR (Net Revenue Retention) = (기초ARR + 확장 - 축소 - 이탈) / 기초ARR × 100
  - NRR > 100%: 기존 고객만으로도 성장
  - 최우량 SaaS: NRR 120%+

Churn Rate (이탈률) = 이탈 고객 수 / 기초 고객 수 × 100
  - 월 2% 이하: 양호 / 월 5%+: 위험

CAC (고객획득비용) = 영업마케팅비 / 신규 고객 수
LTV (고객생애가치) = ARPU × Gross Margin % / Churn Rate
LTV/CAC ≥ 3: 투자 가능 수준 (≥ 5: 우수)
CAC Payback Period = CAC / (ARPU × Gross Margin %)  → 12개월 이내 목표
```

### 성장 지표
```
MoM Growth = (당월 - 전월) / 전월 × 100%
T2D3 법칙 (SaaS): ARR 3배 성장 2년 + 2배 성장 3년

Rule of 40 = YoY Revenue Growth(%) + EBITDA Margin(%)
  → 40 이상: 건전한 성장 (성장 + 수익성 균형)
```

---

## 투자 계약 핵심 조항

### 우선주 종류 (한국 벤처 실무)
| 종류 | 특징 | 실무 |
|---|---|---|
| RCPS (상환전환우선주) | 상환권 + 전환권 | 국내 VC 99% 사용 |
| CPS (전환우선주) | 전환권만 | 해외계 VC |
| Participating Preferred | 청산 시 우선 + 잔여 참여 | 불리, 협상력 약할 때 |

### 주요 투자 조건 (Term Sheet)
```
Pre-money Valuation: 투자 전 기업가치
Post-money = Pre-money + 투자금액
투자자 지분율 = 투자금액 / Post-money

투자조건:
- Anti-dilution (희석방지): Full Ratchet vs Weighted Average
  * Weighted Average (광범위): 업계 표준
  * Full Ratchet: 투자자에게 극히 유리, 협상 난항
- ROFR (선매수권): 기존 주주 먼저 매수 기회
- Tag-Along (동반매도권): 대주주 매각 시 동일 조건 매각 권리
- Drag-Along (강제동반매도권): 과반 동의 시 전체 주주 강제 매각
- 정보권: 월간/분기 재무정보 제공 의무
- 이사 선임권: 투자자 이사 1인 선임 (Series A~)
```

### 청산 우선권 (Liquidation Preference)
```
1x Non-participating:
  청산금 ≥ 투자원금 → 투자원금 우선 수령 후 잔여 미참여
  청산금 < 투자원금 → 투자원금까지만 수령

Participating (참여형):
  투자원금 우선 수령 + 보통주 전환한 것처럼 잔여분도 참여
  → 창업자에게 불리
```

---

## 벤처기업 세제 혜택 (2025 기준)

### 스톡옵션 (주식매수선택권)
- 행사 시 근로소득세 과세 (시가 - 행사가)
- 연간 5,000만원까지 비과세 (벤처기업 임직원)
- 중소·벤처: 행사 시 과세 선택 가능 (퇴직소득세 또는 양도소득세)

### 엔젤투자 소득공제
- 개인투자조합·벤처펀드 출자: 출자금의 10~100% 소득공제
  * 3,000만 이하: 100%
  * 3,000만~5,000만: 70%
  * 5,000만 초과: 30%
- 양도소득 비과세: 중소기업 주식 양도 시

### R&D 세액공제 (스타트업 관련)
- 창업 후 5년 이내: 중소기업 R&D 공제율 25% 적용
- 벤처기업 인증 시 추가 혜택 (일부 세제 감면)

---

## 기업가치 산정 실무 (VC 방식)

### VC Method
```
Post-money = 예상 투자회수금액 / 목표 투자배수(Multiple)
Pre-money = Post-money - 투자금

예) 5년 후 상장 시 시총 500억 예상, 목표 10배 투자수익
    → Post-money = 500억 / 10배 = 50억
    → 투자금 10억이면 Pre-money = 40억
```

### Berkus Method (초기 기업)
| 요소 | 가치 부여 최대 |
|---|---|
| 팀·실행력 | 5억 |
| 기술·IP | 5억 |
| 프로토타입 | 5억 |
| 전략적 관계 | 5억 |
| 제품 출시 및 매출 | 5억 |
최대 25억 (Pre-revenue 기업 상한)

### SAFE (Simple Agreement for Future Equity)
- 한국: 조건부지분인수계약
- 투자금 납입 → 다음 라운드 시 자동 주식 전환
- Valuation Cap 또는 Discount Rate 적용
- 대출도 지분도 아닌 중간 형태 (부채 미계상)
