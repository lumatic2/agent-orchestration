# Task: Investment Bot — Backtest Engine + Momentum Strategy

## Context
Project: C:/Users/1/Desktop/investment-bot/
Existing:
- data/collectors/kis.py, us.py — live data collectors
- data/db/database.py — SQLite (price_history, portfolio_snapshots)
- config/symbols.py — KR_SYMBOLS, US_SYMBOLS
- scheduler/runner.py — APScheduler

## Goal
1. Historical data fetcher (FinanceDataReader for KR, yfinance for US)
2. Backtesting engine (event-driven, vectorized ok for MVP)
3. Momentum strategy: Dual Moving Average Crossover (20-day vs 60-day)
4. Metrics: CAGR, MDD, Sharpe ratio, Win rate
5. CLI runner: python backtest.py --strategy momentum --market KR --symbol 005930

## Files to CREATE

### data/historical.py
Class `HistoricalDataFetcher`:
- `get_kr_ohlcv(symbol: str, start: str, end: str) -> pd.DataFrame`
  - Use `FinanceDataReader` (pip: finance-datareader)
  - Columns: date, open, high, low, close, volume
  - symbol: e.g. "005930"
- `get_us_ohlcv(symbol: str, start: str, end: str) -> pd.DataFrame`
  - Use `yfinance` (pip: yfinance)
  - Same column format
- Both: return DataFrame sorted by date ascending, index=date

### strategy/base.py
Abstract class `BaseStrategy`:
- `__init__(params: dict)`: store params
- `generate_signals(df: pd.DataFrame) -> pd.DataFrame`:
  - Input: OHLCV DataFrame
  - Output: same df + column "signal" (1=buy, -1=sell, 0=hold)
- `name` property → str

### strategy/strategies/momentum.py
Class `MomentumStrategy(BaseStrategy)`:
- Dual Moving Average Crossover
- params: {"fast": 20, "slow": 60}
- Signal logic:
  - fast_ma = close.rolling(fast).mean()
  - slow_ma = close.rolling(slow).mean()
  - signal = 1 when fast_ma crosses above slow_ma (golden cross)
  - signal = -1 when fast_ma crosses below slow_ma (death cross)
  - signal = 0 otherwise (hold current position)
- name = "Momentum (MA Crossover)"

### strategy/backtest.py
Class `Backtester`:
- `__init__(strategy: BaseStrategy, initial_capital: float = 10_000_000)`:
  - initial_capital in KRW (or USD for US stocks)
- `run(df: pd.DataFrame) -> dict`:
  - Apply strategy.generate_signals(df)
  - Simulate trades:
    - On signal=1: buy with all available cash (at next day open)
    - On signal=-1: sell all holdings (at next day open)
    - Track: portfolio_value, cash, holdings per day
  - Apply transaction cost: 0.015% per trade (KR) or 0% (US Alpaca)
  - Return results dict (see below)
- `get_metrics(results: dict) -> dict`:
  - CAGR: (final_value/initial_capital)^(252/n_days) - 1
  - MDD: max drawdown from peak
  - Sharpe: annualized (daily returns mean / std * sqrt(252))
  - Win rate: winning trades / total trades
  - Total return: (final - initial) / initial
  - N trades: number of completed round trips
- `plot(results: dict, save_path: str = None)`:
  - Plot 1: Portfolio value over time vs Buy & Hold
  - Plot 2: Price with MA lines + buy/sell signals marked
  - Use matplotlib, save to save_path if provided, else show

### backtest.py (root level - CLI entry point)
```python
# python backtest.py --strategy momentum --market KR --symbol 005930 --start 2020-01-01
import argparse
from data.historical import HistoricalDataFetcher
from strategy.backtest import Backtester
from strategy.strategies.momentum import MomentumStrategy

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--strategy", default="momentum")
    parser.add_argument("--market", default="KR", choices=["KR", "US"])
    parser.add_argument("--symbol", default="005930")
    parser.add_argument("--start", default="2020-01-01")
    parser.add_argument("--end", default=None)  # defaults to today
    parser.add_argument("--capital", type=float, default=10_000_000)
    parser.add_argument("--fast", type=int, default=20)
    parser.add_argument("--slow", type=int, default=60)
    parser.add_argument("--plot", action="store_true")
    args = parser.parse_args()

    fetcher = HistoricalDataFetcher()
    if args.market == "KR":
        df = fetcher.get_kr_ohlcv(args.symbol, args.start, args.end)
    else:
        df = fetcher.get_us_ohlcv(args.symbol, args.start, args.end)

    strategy = MomentumStrategy({"fast": args.fast, "slow": args.slow})
    bt = Backtester(strategy, initial_capital=args.capital)
    results = bt.run(df)
    metrics = bt.get_metrics(results)

    print(f"\n=== {strategy.name} | {args.symbol} ({args.market}) ===")
    print(f"기간: {args.start} ~ {results['end_date']}")
    print(f"초기 자본: {args.capital:,.0f}")
    print(f"최종 자산: {results['final_value']:,.0f}")
    print(f"총 수익률: {metrics['total_return']:+.2%}")
    print(f"CAGR: {metrics['cagr']:+.2%}")
    print(f"MDD: {metrics['mdd']:.2%}")
    print(f"Sharpe: {metrics['sharpe']:.2f}")
    print(f"승률: {metrics['win_rate']:.1%}")
    print(f"거래 횟수: {metrics['n_trades']}")

    if args.plot:
        bt.plot(results, save_path=f"backtest_{args.symbol}_{args.strategy}.png")
        print(f"\n차트 저장: backtest_{args.symbol}_{args.strategy}.png")

if __name__ == "__main__":
    main()
```

## Files to MODIFY

### requirements.txt
Add:
- finance-datareader
- yfinance
- matplotlib

### strategy/__init__.py
Create empty file.

### strategy/strategies/__init__.py
Create empty file.

## Constraints
- Python 3.10 compatible (no match/case, use float | None not union type hints for 3.9)
- No forward-fill abuse — handle NaN from rolling properly (skip first N rows)
- Transaction cost applied on both buy and sell
- Buy & Hold benchmark: buy on first day, hold to end
- matplotlib non-interactive backend for Windows: use `matplotlib.use('Agg')` before import pyplot only when saving to file
- FinanceDataReader may return Korean column names — normalize to lowercase english

## Done Criteria
- `pip install -r requirements.txt` installs cleanly
- `python backtest.py --strategy momentum --market KR --symbol 005930 --start 2020-01-01` prints metrics
- `python backtest.py --market US --symbol AAPL --start 2020-01-01 --plot` saves chart
