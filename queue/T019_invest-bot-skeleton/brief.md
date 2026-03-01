# Task: Investment Bot — Project Skeleton + Data Collectors

## Goal
Create a Python investment automation project skeleton with:
1. Project structure setup with venv
2. KIS API data collector (Korean stocks, READ-ONLY: quotes + balance)
3. Alpaca data collector (US stocks, paper trading: quotes + account info)
4. SQLite database module for storing market data
5. Config/env loading module

## Project Location
`C:/Users/1/Desktop/investment-bot/`

## Directory Structure to Create
```
investment-bot/
├── .env.example          # Template for API keys (no real keys)
├── requirements.txt      # Dependencies
├── README.md             # Setup instructions
├── config/
│   └── settings.py       # Load .env, central config
├── data/
│   ├── __init__.py
│   ├── collectors/
│   │   ├── __init__.py
│   │   ├── base.py       # Abstract BaseCollector class
│   │   ├── kis.py        # KIS OpenAPI collector
│   │   └── us.py         # Alpaca collector
│   └── db/
│       ├── __init__.py
│       └── database.py   # SQLite setup, schema, CRUD helpers
├── portfolio/
│   ├── __init__.py
│   └── tracker.py        # Placeholder - balance + positions fetch
└── main.py               # Entry point: test connections, print balance
```

## Specifications

### config/settings.py
- Use `python-dotenv` to load .env
- Export: KIS_APP_KEY, KIS_APP_SECRET, KIS_ACCOUNT_NO, KIS_IS_REAL (bool)
- Export: ALPACA_API_KEY, ALPACA_API_SECRET, ALPACA_BASE_URL
- Export: DB_PATH (default: data/invest.db)

### data/collectors/base.py
- Abstract class `BaseCollector` with methods:
  - `get_access_token()` → str
  - `get_price(symbol: str)` → dict
  - `get_balance()` → dict

### data/collectors/kis.py
KIS OpenAPI (REST, real account domain: https://openapi.koreainvestment.com:9443)
- `KISCollector(BaseCollector)`:
  - `get_access_token()`: POST /oauth2/tokenP with app_key, app_secret, grant_type
  - `get_price(symbol)`: GET /uapi/domestic-stock/v1/quotations/inquire-price
    - tr_id: "FHKST01010100"
    - Headers: authorization, appkey, appsecret, tr_id
    - Return: {"symbol", "name", "current_price", "change_rate", "volume"}
  - `get_balance()`: GET /uapi/domestic-stock/v1/trading/inquire-balance
    - tr_id: "TTTC8434R" (real account)
    - Return: {"total_eval_amount", "profit_loss_rate", "positions": [...]}
- Token caching: save token + expiry to file (tokens/kis_token.json), reuse if valid

### data/collectors/us.py
Alpaca paper trading (base_url: https://paper-api.alpaca.markets)
- `AlpacaCollector(BaseCollector)`:
  - `get_access_token()`: returns API key (no OAuth needed)
  - `get_price(symbol)`: GET /v2/stocks/{symbol}/quotes/latest
    - Return: {"symbol", "bid_price", "ask_price", "mid_price"}
  - `get_account()`: GET /v2/account
    - Return: {"equity", "cash", "buying_power", "portfolio_value"}
  - `get_balance()`: calls get_account()
- Use `alpaca-py` library

### data/db/database.py
SQLite schema:
```sql
CREATE TABLE IF NOT EXISTS price_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    symbol TEXT NOT NULL,
    market TEXT NOT NULL,  -- 'KR', 'US', 'CRYPTO'
    price REAL NOT NULL,
    volume REAL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS portfolio_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    total_value REAL,
    cash REAL,
    positions TEXT,  -- JSON string
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
```
- `init_db()`: create tables if not exist
- `save_price(symbol, market, price, volume)`: insert
- `get_price_history(symbol, limit=100)`: select recent

### portfolio/tracker.py
- `PortfolioTracker`: takes KISCollector + AlpacaCollector
- `snapshot()`: fetch balance from both, save to DB, return combined dict
  - Return: {"kr": {...}, "us": {...}, "total_krw": estimated total}

### main.py
- Load config
- Init DB
- Test KIS connection: get token, get price for "005930" (Samsung)
- Test Alpaca connection: get account info, get price for "AAPL"
- Print results clearly
- Catch errors gracefully with helpful messages

### .env.example
```
KIS_APP_KEY=your_app_key_here
KIS_APP_SECRET=your_app_secret_here
KIS_ACCOUNT_NO=your_account_number  # format: 50123456-01
KIS_IS_REAL=true

ALPACA_API_KEY=your_alpaca_key
ALPACA_API_SECRET=your_alpaca_secret

DB_PATH=data/invest.db
```

### requirements.txt
```
python-dotenv
requests
alpaca-py
pandas
sqlalchemy
```

## Constraints
- NO real API keys in any file
- READ-ONLY for KIS (no order endpoints)
- All API calls wrapped in try/except with clear error messages
- Korean comments OK for Korean-specific code
- Create `tokens/` directory with .gitignore
- Create `.gitignore` (exclude .env, tokens/, data/*.db, __pycache__)

## Done Criteria
- All files created with working code (no placeholders except tracker.py)
- `python main.py` runs without import errors
- KIS token fetch logic is correct per official API docs
- Alpaca account fetch works with paper trading URL
