# Task: DART OpenAPI 연동 + 백테스터 과거 데이터 수정

## 프로젝트 위치
C:/Users/1/Desktop/investment-bot/

## 목적
한국 소형주 퀀트 전략 백테스터에서 과거 시점별 PER/PBR/ROE를 계산하기 위해
DART OpenAPI로 연도별 EPS/BPS를 가져오고, MT9 시그널도 과거 날짜 기준으로 수정한다.

현재 문제:
- get_fundamentals()가 Naver Finance 현재 데이터만 반환 -> 과거 날짜에 미래 데이터 사용
- get_mt9_signal()이 현재 S&P500만 조회 -> 과거 날짜에도 오늘 신호 적용 -> 전 기간 HALT

## 수정/생성할 파일 (5개)

---

### 1. 신규 생성: data/collectors/dart.py

DARTCollector 클래스. requests 직접 사용 (외부 라이브러리 없이).
캐시는 JSON 파일로 저장 (data/cache/dart/ 폴더).

핵심 메서드:
- __init__(api_key=None, request_delay=0.5): env DART_API_KEY 사용
- _get_corp_map(): corpCode.xml 다운로드 -> stock_code:corp_code 매핑 DataFrame
  캐시: data/cache/dart/corp_map.json (24시간 유효, mtime 체크)
- _stock_to_corp_code(stock_code: str) -> str | None
- _fetch_statement(corp_code, year, reprt_code='11011', fs_div='CFS') -> pd.DataFrame
  fnlttSinglAcntAll.json 호출
  캐시: data/cache/dart/{corp_code}_{year}_{reprt_code}_{fs_div}.json
  status '000' = 성공
- _extract_eps_bps(df: pd.DataFrame) -> dict:
  EPS: df where sj_div in ['IS','CIS'] and account_nm contains '기본주당'
  BPS: df where sj_div=='BS' and account_nm contains '주당순자산' or '주당장부'
  thstrm_amount 파싱: 쉼표 제거 후 float
- get_point_in_time_year(as_of_date: str) -> tuple[int, str]:
  as_of_date 기준 실제로 공시된 데이터 반환 (Look-Ahead Bias 방지)
  4월 이후 -> (year-1, '11011') 전년도 사업보고서
  9월 이후 -> (year, '11012') 당해년도 반기보고서
  1~3월 -> (year-2, '11011') 전전년도 사업보고서
- get_fundamentals_as_of(tickers: list[str], as_of_date: str) -> pd.DataFrame:
  Returns DataFrame indexed by ticker, columns: EPS, BPS, ROE(=EPS/BPS*100)
  연결재무제표(CFS) 우선, 없으면 별도재무제표(OFS) 폴백
  0.5초 sleep per request

API 엔드포인트:
- corpCode.xml: https://opendart.fss.or.kr/api/corpCode.xml?crtfc_key={key}
- fnlttSinglAcntAll.json: https://opendart.fss.or.kr/api/fnlttSinglAcntAll.json
  params: crtfc_key, corp_code, bsns_year, reprt_code, fs_div

캐시 구조 (JSON):
- corp_map.json: {"records": [{"stock_code": "005930", "corp_code": "00126380", "corp_name": "삼성전자"},...], "cached_at": "2026-03-01T00:00:00"}
- {corp_code}_{year}_{reprt_code}_{fs_div}.json: DART API 응답 list 그대로 저장

---

### 2. 수정: strategy/strategies/smallcap_quant.py

변경 1: get_mt9_signal(date=None) - date 파라미터 추가

date가 None이면 오늘 날짜 사용 (기존 동작 유지).
date가 있으면 해당 날짜 기준 과거 S&P500 데이터 60일치 다운로드 후 MA20 계산.
yfinance download: start=end_dt-60days, end=end_dt+1day, ticker='^GSPC'
close.rolling(20).mean()의 마지막 값과 close 마지막 값 비교.

변경 2: rank_universe(date, krx_collector, dart_collector=None)

dart_collector가 None이 아니면:
  1. F-score 통과 tickers 목록으로 dart_collector.get_fundamentals_as_of(tickers, date) 호출
  2. 반환된 EPS, BPS, ROE로 merged DataFrame 업데이트 (기존 Naver ROE 대체)
  3. pykrx get_market_ohlcv_by_date로 해당 날짜 주가 조회
  4. PER = 주가 / EPS, PBR = 주가 / BPS 계산해서 merged에 저장
dart_collector가 None이면: 기존 Naver 방식 그대로

date 파라미터를 get_mt9_signal(date)에 넘겨서 과거 날짜 기준 MT9 체크.

---

### 3. 수정: strategy/quant_backtest.py

- __init__에 dart_collector=None 파라미터 추가, self.dart_collector = dart_collector 저장
- run() 루프:
  - self.strategy.get_mt9_signal() -> self.strategy.get_mt9_signal(date_str)
  - self.strategy.rank_universe(date_str, self.krx_collector) -> self.strategy.rank_universe(date_str, self.krx_collector, self.dart_collector)

---

### 4. 수정: backtest_quant.py

argparse에 추가:
  --dart-api-key: DART OpenAPI key (default: env DART_API_KEY)

DARTCollector 초기화 (키가 없으면 dart=None, Naver 폴백):
  api_key = args.dart_api_key or os.environ.get('DART_API_KEY', '')
  if api_key:
      try: dart = DARTCollector(api_key=api_key)
      except: dart = None

QuantBacktester 생성 시 dart_collector=dart 전달.

---

### 5. 확인: requirements.txt

requests, beautifulsoup4, pykrx, yfinance 있는지 확인. 없으면 추가.
신규 외부 라이브러리는 추가하지 않음 (dart는 requests로 직접 구현).

---

## 제약 사항

1. dart_collector=None이면 기존 Naver 방식 그대로 동작 (하위호환 필수)
2. 모든 DART API 호출은 data/cache/dart/ 폴더에 JSON 캐싱 (중복 요청 방지)
3. DART API 키는 환경변수 DART_API_KEY 또는 파라미터로 받음
4. 로깅: logger = logging.getLogger(__name__) 패턴 유지
5. 에러 시 float('nan') 반환, 예외 전파 금지
6. data/cache/dart/ 디렉토리 자동 생성

## 완료 기준

모든 파일 수정/생성 후 다음 임포트 성공:
  python -c "from data.collectors.dart import DARTCollector; print('OK')"
  python -c "from strategy.strategies.smallcap_quant import SmallCapQuantStrategy; s = SmallCapQuantStrategy({}); r = s.get_mt9_signal('2020-01-15'); print('MT9 2020-01-15:', r)"
