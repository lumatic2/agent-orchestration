# Task: 젠포트 조건식을 투자봇에 반영

## 프로젝트 위치
C:/Users/1/Desktop/investment-bot/

## 목표
강환국 젠포트 전략의 조건식 패턴을 투자봇에 구현한다.
기존 5팩터 소형주 퀀트 전략(SmallCapQuantStrategy)에
신 F-score, GP/A 팩터, 복합 밸류 팩터를 추가하고
전략 모드(슈퍼퀄리티/울트라/신마법공식)를 선택 가능하게 만든다.

---

## 젠포트 조건식 스펙 (구현 대상)

### 신 F-score (3항목) — 기존 F-score 대체
1. 당기순이익 > 0
2. 영업현금흐름(CFO) > 0
3. 신주발행 없음: 총발행주식수 증가 없음 (당해년도 - 전년도 <= 0)

### 팩터 추가
- **GP/A**: 매출총이익 / 자산총계 (높을수록 좋음, 우선순위 팩터)
- **PSR**: 주가 / 주당매출액 (낮을수록 좋음)
- **PCR**: 주가 / 주당영업현금흐름 (낮을수록 좋음)
- **영업이익 성장률(YoY)**: (당해 - 전년) / abs(전년) (양수 필터)

### 전략 모드
- **super_quality**: 신 F-score 3항목 필터 + GP/A 순위 (기관 팩터 대체)
- **ultra**: PER+PBR+PSR+PCR 복합 밸류 + GP/A 퀄리티 + 영업이익 성장 필터
- **magic_formula**: PER + GP/A 순위 합산 (신 마법공식)
- **value_composite**: PER+PBR+PSR+PCR 순위 합산 (소형주 가치)
- **default** (기존): 기존 5팩터 그대로 (하위 호환 유지)

---

## 수정/생성할 파일 (3개)

### 1. data/collectors/dart.py (수정)

`_extract_eps_bps` 메서드 확장:
현재 EPS, ROE 추출에서 → 아래 항목도 추가 추출:
- `CFO` (영업현금흐름): sj_div=='CF' and account_nm contains '영업활동으로 인한 현금흐름' or '영업활동 현금흐름'
- `gross_profit` (매출총이익): sj_div in ['IS','CIS'] and account_nm == '매출총이익'
- `total_assets` (자산총계): sj_div=='BS' and account_nm == '자산총계'
- `revenue` (매출액): sj_div in ['IS','CIS'] and account_nm in ['매출액', '수익(매출액)']
- `shares_current` (당해 발행주식수): sj_div=='BS' and account_nm contains '주식수' or IS/CIS '가중평균주식수'
  → 없으면 NaN으로 유지 (증자 필터는 NaN이면 skip)

전년도 데이터 추출을 위해 `thstrm_amount` 외에 `frmtrm_amount` (전년도)도 파싱:
- `prev_gross_profit`: 전년도 매출총이익 (from frmtrm_amount)
- `prev_operating_income`: 전년도 영업이익 (from frmtrm_amount)

반환 dict에 새 키 추가:
```python
result = {
    "EPS": nan, "BPS": nan, "ROE": nan,
    "CFO": nan, "gross_profit": nan, "total_assets": nan, "revenue": nan,
    "operating_income": nan,
    "prev_gross_profit": nan, "prev_operating_income": nan,
}
```

`get_fundamentals_as_of` 메서드 수정:
반환 DataFrame 컬럼에 새 항목 추가:
columns = ["EPS", "BPS", "ROE", "CFO", "gross_profit", "total_assets", "revenue", "operating_income", "prev_operating_income"]

### 2. strategy/strategies/smallcap_quant.py (수정)

#### `__init__` 파라미터 추가
```python
self.strategy_mode: str = p.get("strategy_mode", "default")
# 옵션: "default", "super_quality", "ultra", "magic_formula", "value_composite"
```

#### `_apply_fscore_filter` 메서드 수정
- strategy_mode == "default": 기존 로직 유지 (EPS>0, PBR>0.2, ROE>0)
- 그 외 모드: 신 F-score 3항목 적용
  1. net_income > 0: EPS > 0 (기존과 동일하나 column명 주의)
  2. CFO > 0: df["CFO"] 컬럼 있고 notna이면 적용
  3. shares_no_increase: shares_delta <= 0 (없으면 skip)

#### `_score_factors` 메서드 수정
strategy_mode별 팩터 합산:

**super_quality**:
- 기존 PER, PBR, ROE, momentum 유지
- institutional 팩터 → GP/A 팩터로 교체 (GP/A = gross_profit / total_assets)
- weights: per=0.25, pbr=0.20, roe=0.20, momentum=0.20, gpa=0.15

**ultra**:
- value_composite = PER+PBR+PSR+PCR 합산 순위 (낮을수록 좋음) → invert
  - PSR 계산: 주가(price) / (revenue / shares_outstanding)  
    → price는 dart_collector를 통해 rank_universe 시 이미 계산된 PER/EPS에서 역산:
    price = PER × EPS (단, 이미 pykrx 주가를 가져오는 로직 있음)
  - PCR 계산: 주가 / (CFO / shares_outstanding)
    → shares_outstanding은 market_cap / price 로 추정
  - PSR, PCR을 계산하기 위해 price와 per_share 수치 필요 → 가능한 경우만 적용, NaN이면 0.5
- 영업이익 성장 필터: operating_income > prev_operating_income (YoY > 0) — 데이터 없으면 skip
- weights: value_composite=0.40, gpa=0.25, roe=0.15, momentum=0.20

**magic_formula**:
- per_rank (낮을수록 좋음, invert)
- gpa_rank (높을수록 좋음)
- 합산 순위로 정렬
- weights: per=0.50, gpa=0.50, momentum 제외

**value_composite**:
- PER + PBR + PSR + PCR 합산 순위 (낮을수록 좋음)
- weights: per=0.25, pbr=0.25, psr=0.25, pcr=0.25

#### `rank_universe` 메서드 수정
dart_collector가 있을 때 GP/A, CFO, revenue 계산:
- dart_fund에서 gross_profit, total_assets, revenue, CFO, operating_income 가져옴
- filtered["GP_A"] = dart_fund["gross_profit"] / dart_fund["total_assets"]
- PSR 계산 (가능한 경우):
  - shares_est = filtered["market_cap"] / price_series  (market_cap은 universe df에서)
  - filtered["PSR"] = price_series / (dart_fund["revenue"] / shares_est)
- PCR 계산:
  - filtered["PCR"] = price_series / (dart_fund["CFO"] / shares_est)
- filtered["operating_income_growth"] = dart_fund["operating_income"] > dart_fund["prev_operating_income"]

strategy_mode == "ultra"일 때 영업이익 성장 필터 추가:
```python
if self.strategy_mode == "ultra" and "operating_income_growth" in filtered.columns:
    growth_mask = filtered["operating_income_growth"].fillna(True)
    filtered = filtered[growth_mask]
```

### 3. backtest_quant.py (수정)

argparse에 파라미터 추가:
```python
parser.add_argument("--strategy-mode", default="default",
    choices=["default", "super_quality", "ultra", "magic_formula", "value_composite"],
    help="젠포트 전략 모드 (default=기존 5팩터)")
```

SmallCapQuantStrategy 생성 시 strategy_mode 전달:
```python
strategy = SmallCapQuantStrategy({
    ...,
    "strategy_mode": args.strategy_mode,
})
```

---

## 제약 사항

1. strategy_mode="default" 이면 기존 동작 완전 동일 (하위 호환 필수)
2. dart_collector=None 이면 모든 신규 팩터(GP/A, PSR, PCR, CFO)는 NaN 처리, 기존 팩터만으로 동작
3. 새 팩터 데이터 없을 때는 해당 팩터 가중치를 나머지에 균등 분배하지 말고
   그냥 해당 팩터 점수를 0.5(중립)로 처리
4. DART _extract_eps_bps에서 새 계정과목 추출 시 기존 EPS/ROE 로직 건드리지 말 것
5. 에러 시 float('nan') 반환, 예외 전파 금지
6. 로깅: logger.info로 strategy_mode 및 유효 팩터 개수 로그

## 완료 기준

```bash
cd C:/Users/1/Desktop/investment-bot
python -c "
from strategy.strategies.smallcap_quant import SmallCapQuantStrategy
s1 = SmallCapQuantStrategy({'strategy_mode': 'default'})
s2 = SmallCapQuantStrategy({'strategy_mode': 'super_quality'})
s3 = SmallCapQuantStrategy({'strategy_mode': 'ultra'})
s4 = SmallCapQuantStrategy({'strategy_mode': 'magic_formula'})
print('All modes OK:', s1.name, s2.strategy_mode, s3.strategy_mode, s4.strategy_mode)
"
python -c "
from data.collectors.dart import DARTCollector
d = DARTCollector()
print('DART CFO fields OK')
"
python backtest_quant.py --help | grep strategy-mode
```
