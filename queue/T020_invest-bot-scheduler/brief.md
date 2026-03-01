# Task: Investment Bot — Data Collection Scheduler (3단계 B)

## Context
Project is at: C:/Users/1/Desktop/investment-bot/
Existing structure:
- config/settings.py (loads .env)
- data/collectors/kis.py (KISCollector)
- data/collectors/us.py (AlpacaCollector)
- data/db/database.py (init_db, save_price, get_price_history)
- portfolio/tracker.py (PortfolioTracker)
- main.py (connection test)

## Goal
Add a market data scheduler that:
1. Collects KR stock prices during KR market hours (09:00–15:30 KST, Mon–Fri)
2. Collects US stock prices during US market hours (09:30–16:00 ET, Mon–Fri)
3. Saves all prices to SQLite via existing save_price()
4. Runs continuously with APScheduler
5. Logs activity clearly

## Files to CREATE

### scheduler/jobs.py
- `collect_kr_prices(kis: KISCollector, symbols: list[str])`:
  - Check if current time is within KR market hours (09:00–15:30 KST)
  - If yes: call kis.get_price(symbol) for each symbol, call save_price()
  - Log result or skip message if outside hours
- `collect_us_prices(alpaca: AlpacaCollector, symbols: list[str])`:
  - Check if current time is within US market hours (09:30–16:00 ET, Mon–Fri)
  - If yes: call alpaca.get_price(symbol) for each, call save_price()
  - Log result or skip message if outside hours
- Both functions: catch exceptions per symbol (one failure shouldn't stop others)

### scheduler/runner.py
- Use APScheduler (BackgroundScheduler)
- Schedule `collect_kr_prices` every 5 minutes
- Schedule `collect_us_prices` every 5 minutes
- KR symbols (default): ["005930", "000660", "035420"]  # 삼성전자, SK하이닉스, NAVER
- US symbols (default): ["AAPL", "MSFT", "NVDA", "SPY", "QQQ"]
- On start: init_db(), print schedule summary
- Run until KeyboardInterrupt (Ctrl+C)
- On shutdown: clean scheduler stop

### config/symbols.py
- KR_SYMBOLS: list of Korean stock codes to track
- US_SYMBOLS: list of US symbols to track
- Easy to edit by user

## Files to MODIFY

### data/db/database.py
- Add `get_latest_prices(market: str) -> list[dict]` — return most recent price per symbol for given market

### main.py
- Add option to run scheduler: `python main.py --scheduler`
- Keep existing connection test as default (no args)
- Use argparse

## Constraints
- Use `pytz` for timezone handling (KST = Asia/Seoul, ET = America/New_York)
- APScheduler already in requirements.txt — if not, add it
- No new dependencies beyond pytz + apscheduler
- Add `pytz` and `apscheduler` to requirements.txt if missing
- Logging: use Python's `logging` module (not print) in scheduler, INFO level
- main.py keeps backward compatibility (python main.py still works)

## Done Criteria
- `python main.py --scheduler` starts without errors
- Prints schedule summary on start
- Logs "collected price" or "outside market hours, skipping" every 5 min
- Ctrl+C shuts down cleanly
