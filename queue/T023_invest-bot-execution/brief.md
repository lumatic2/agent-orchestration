# Task: Investment Bot — Order Execution Module (모의투자)

## Context
Project: C:/Users/1/Desktop/investment-bot/
Existing:
- data/collectors/kis.py — KISCollector (real account read-only)
- data/collectors/us.py — AlpacaCollector (paper trading)
- data/historical.py — HistoricalDataFetcher (FinanceDataReader + yfinance)
- strategy/base.py — BaseStrategy
- strategy/strategies/momentum.py — MomentumStrategy (fast=20, slow=60 MA crossover)
- strategy/backtest.py — Backtester
- config/settings.py — loads .env
- scheduler/runner.py — APScheduler

## Goal
Build order execution module connected to:
- KIS 모의투자 (virtual trading): https://openapivts.koreainvestment.com:29443
- Alpaca Paper Trading: already configured

## KIS 모의투자 API Info
- Base URL: https://openapivts.koreainvestment.com:29443
- Same app_key, app_secret as real account
- Token endpoint: /oauth2/tokenP (same as real)
- tr_id for virtual account:
  - Buy order: VTTC0802U
  - Sell order: VTTC0801U
  - Balance inquiry: VTTC8434R
- Order endpoint: /uapi/domestic-stock/v1/trading/order-cash
- Buy/Sell params: CANO, ACNT_PRDT_CD, PDNO(symbol), ORD_DVSN="01"(market), ORD_QTY, ORD_UNPR="0"

## Files to CREATE

### execution/__init__.py
Empty.

### execution/order.py
Dataclass Order with fields:
- symbol: str
- side: str  # "buy" or "sell"
- qty: int
- order_type: str  # "market"
- price: float  # 0 for market orders
- market: str  # "KR" or "US"
- status: str  # "pending", "filled", "failed"
- order_id: str = ""
- filled_at: str = ""
- message: str = ""

### execution/broker.py
Abstract class BaseBroker with methods:
- place_order(order: Order) -> Order
- get_position(symbol: str) -> dict
- get_positions() -> list
- get_cash() -> float

### execution/kis_broker.py
Class KISVirtualBroker(BaseBroker):
- base_url = settings.KIS_VIRTUAL_BASE_URL (https://openapivts.koreainvestment.com:29443)
- Same app_key, app_secret, account_no as real account from settings
- Token: POST /oauth2/tokenP, cache to tokens/kis_virtual_token.json
- place_order(order):
  POST /uapi/domestic-stock/v1/trading/order-cash
  Headers: authorization Bearer token, appkey, appsecret, tr_id (VTTC0802U buy / VTTC0801U sell)
  Body: CANO, ACNT_PRDT_CD, PDNO=symbol, ORD_DVSN="01", ORD_QTY=str(qty), ORD_UNPR="0"
  On rt_cd="0": order.status="filled", order.order_id from output.ODNO
  On error: order.status="failed", order.message=error
- get_positions(): GET /uapi/domestic-stock/v1/trading/inquire-balance, tr_id=VTTC8434R
- get_position(symbol): filter get_positions() by symbol
- get_cash(): from output2[0].dnca_tot_amt

### execution/alpaca_broker.py
Class AlpacaBroker(BaseBroker):
- Use alpaca-py TradingClient with paper=True
- place_order(order): MarketOrderRequest, OrderSide.BUY/SELL, TimeInForce.DAY
- get_position(symbol): TradingClient.get_open_position(symbol), catch exception return empty dict
- get_positions(): TradingClient.get_all_positions()
- get_cash(): float(account.cash)

### execution/risk.py
Class RiskManager:
- __init__(max_position_pct=0.05, daily_loss_limit_pct=0.02, max_single_order_pct=0.05)
- calc_position_size(cash, price, total_portfolio) -> int:
  max_spend = min(cash, total_portfolio * max_single_order_pct)
  return max(0, int(max_spend / price))
- check_daily_loss(current_value, start_of_day_value) -> bool:
  Returns True if safe to trade

### execution/live_runner.py
Class LiveStrategyRunner:
- __init__(strategy, broker, risk, fetcher, market, symbols)
- run_once(symbol, dry_run=True):
  1. Fetch 120 days OHLCV via fetcher
  2. Generate signals, take last signal value
  3. Get current position for symbol
  4. Action logic: signal=1 + no position -> BUY; signal=-1 + has position -> SELL; else HOLD
  5. If BUY: calc qty via risk manager
  6. If dry_run: log action without placing order
  7. If not dry_run and qty > 0: broker.place_order()
  8. Log result clearly
- run_all(dry_run=True): loop run_once for all symbols

### live.py (root level)
CLI entry point:
- Args: --market (KR/US), --symbol, --execute (flag), --fast, --slow
- Default dry_run=True. Only trade when --execute passed.
- Print [DRY RUN] or [LIVE TRADING] mode clearly
- For KR: KISVirtualBroker; For US: AlpacaBroker
- Create runner and call run_once

## Files to MODIFY

### scheduler/runner.py
Add job at 09:05 KST Mon-Fri:
- Run live_runner.run_all(dry_run=True)
- Log: "Live trading check (DRY RUN mode)"

### config/settings.py
Add: KIS_VIRTUAL_BASE_URL = os.getenv("KIS_VIRTUAL_BASE_URL", "https://openapivts.koreainvestment.com:29443")

### .env.example
Add: KIS_VIRTUAL_BASE_URL=https://openapivts.koreainvestment.com:29443

## Constraints
- DEFAULT always dry_run=True. Real orders only with --execute flag.
- Never place order if qty <= 0
- Never sell if no position exists
- All API calls: try/except, log error, never crash
- Use Python logging module inside modules; live.py uses print for user output

## Done Criteria
- python live.py --market KR --symbol 005930 -> prints signal + "DRY RUN: would BUY/SELL/HOLD"
- python live.py --market KR --symbol 005930 --execute -> places order on KIS 모의투자
- No crashes on missing position or zero cash
