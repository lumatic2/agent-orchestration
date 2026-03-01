# Task: Investment Bot — Portfolio Tracker + Notion Auto-Update

## Context
Project: C:/Users/1/Desktop/investment-bot/
Existing files (DO NOT break):
- config/settings.py — loads .env (KIS, Alpaca, DB_PATH)
- data/collectors/kis.py — KISCollector (get_price, get_balance, get_access_token)
- data/collectors/us.py — AlpacaCollector (get_price, get_account, get_balance)
- data/db/database.py — init_db, save_price, get_price_history, get_latest_prices, save_portfolio_snapshot
- portfolio/tracker.py — PortfolioTracker.snapshot() → returns {kr, us, total_krw}
- scheduler/runner.py — APScheduler, collect_kr_prices + collect_us_prices every 5min
- main.py — python main.py (test) | python main.py --scheduler

## Goal
1. Enhance PortfolioTracker with returns calculation
2. Add Notion notifier that updates the "개인 투자 현황" page
3. Add portfolio snapshot job to scheduler (every 30 min)
4. Add NOTION_TOKEN + NOTION_PORTFOLIO_PAGE_ID to config

## Notion Info
- Personal Notion API token env var: PERSONAL_NOTION_TOKEN
- Portfolio page ID: 30e85046-ff55-8195-a4f9-cc27e14757a4
- Notion API base: https://api.notion.com/v1
- Notion API version header: "2022-06-28"
- The page has existing blocks — use PATCH to update, not create new pages
- Strategy: delete all non-child_page blocks, then append fresh content blocks

## Files to CREATE

### notify/notion_updater.py
Class `NotionPortfolioUpdater`:
- `__init__(token, page_id)`: set headers with Bearer token + Notion-Version
- `_get_blocks()` → list all blocks via GET /blocks/{page_id}/children
- `_delete_blocks(block_ids)` → DELETE each block (skip type=child_page)
- `_append_blocks(blocks)` → PATCH /blocks/{page_id}/children with children array
- `update(snapshot: dict)`:
  1. Call _get_blocks(), filter out child_page types, delete the rest
  2. Build fresh content blocks from snapshot data (see format below)
  3. Call _append_blocks() with new content
  4. Log success

Content blocks to generate from snapshot:
```
# 포트폴리오 현황  (heading_1)
마지막 업데이트: {timestamp} KST  (paragraph)

## 자산 요약  (heading_2)
총 평가금액: {total_krw:,.0f} 원  (paragraph)
한국주식: {kr_total:,.0f} 원  (paragraph)
미국주식: {us_total_krw:,.0f} 원 (≈ ${us_usd:,.0f})  (paragraph)
현금: {cash_krw:,.0f} 원  (paragraph)

## 수익률  (heading_2)
당일 손익: {daily_pnl:+,.0f} 원 ({daily_pnl_rate:+.2f}%)  (paragraph)
누적 손익: {total_pnl:+,.0f} 원 ({total_pnl_rate:+.2f}%)  (paragraph)

## 한국주식 보유종목  (heading_2)
[table with columns: 종목명, 수량, 평가금액, 손익, 수익률]  → use bulleted_list_item blocks

## 미국주식 포지션  (heading_2)
[positions from Alpaca if any, else "보유 종목 없음"]  → bulleted_list_item
```

Use Notion block format (rich_text arrays). Keep it simple — paragraph + heading_2 + bulleted_list_item only.

### notify/__init__.py
Empty.

## Files to MODIFY

### config/settings.py
Add:
```python
NOTION_TOKEN = os.getenv("PERSONAL_NOTION_TOKEN", "")
NOTION_PORTFOLIO_PAGE_ID = os.getenv(
    "NOTION_PORTFOLIO_PAGE_ID",
    "30e85046-ff55-8195-a4f9-cc27e14757a4"
)
```

### portfolio/tracker.py
Enhance snapshot() to also calculate:
- `daily_pnl`: current total_krw minus earliest snapshot of today from DB (or 0 if first)
- `daily_pnl_rate`: daily_pnl / yesterday_total * 100
- `total_pnl`: current total_krw minus first ever snapshot from DB (or 0 if first)
- `total_pnl_rate`: total_pnl / first_total * 100
- `us_total_krw`: us_portfolio_value * usdkrw_rate
- `cash_krw`: us cash * usdkrw_rate
- `timestamp`: current KST time string "YYYY-MM-DD HH:MM"
Include all of the above in the returned dict.

Add method `snapshot_and_notify()`:
- calls snapshot()
- if NOTION_TOKEN is set: calls NotionPortfolioUpdater.update(snapshot)
- returns snapshot

### data/db/database.py
Add:
- `get_first_snapshot()` → dict or None — oldest portfolio_snapshots row
- `get_today_first_snapshot()` → dict or None — earliest snapshot of today (KST)

### scheduler/runner.py
Add portfolio snapshot job:
- Import PortfolioTracker, KISCollector, AlpacaCollector
- Schedule `tracker.snapshot_and_notify()` every 30 minutes
- Log "Portfolio snapshot saved + Notion updated" on success

### .env.example
Add:
```
PERSONAL_NOTION_TOKEN=your_notion_token
NOTION_PORTFOLIO_PAGE_ID=30e85046-ff55-8195-a4f9-cc27e14757a4
```

## Constraints
- No new pip packages — use `requests` for Notion API calls (already installed)
- usdkrw_rate = 1350.0 (update from 1300)
- All Notion API calls: try/except with logging, never crash the scheduler
- NOTION_TOKEN missing → skip Notion update silently (log warning only)
- Alpaca is paper trading → positions list will be empty, show "보유 종목 없음"

## Done Criteria
- `python main.py --scheduler` still works
- Portfolio snapshot runs every 30 min
- Notion page "개인 투자 현황" gets updated with fresh data each run
- No crashes if Notion token missing or API fails
