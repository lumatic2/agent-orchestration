# Task: Investment Bot — Telegram Bot Notification

## Context
Project: C:/Users/1/Desktop/investment-bot/
Existing:
- config/settings.py — loads .env
- scheduler/runner.py — APScheduler (시세수집, 포트폴리오, 매매신호)
- execution/live_runner.py — LiveStrategyRunner.run_once() returns action info
- portfolio/tracker.py — PortfolioTracker.snapshot_and_notify()
- notify/notion_updater.py — Notion updater

New .env vars already added:
- TELEGRAM_BOT_TOKEN
- TELEGRAM_CHAT_ID

## Goal
Add Telegram bot notifications for:
1. 매매 신호 발생 (BUY/SELL) — 즉시 알림
2. HOLD — 알림 없음
3. 포트폴리오 스냅샷 — 30분마다 간단 요약
4. 에러 발생 — 즉시 알림
5. 스케줄러 시작/종료 — 알림

## Files to CREATE

### notify/telegram_notifier.py
Class TelegramNotifier:
- __init__(token, chat_id):
  - self.token, self.chat_id
  - self.base_url = f"https://api.telegram.org/bot{token}"
  - if not token or not chat_id: self.disabled = True, log warning
- send(message: str) -> bool:
  - POST {base_url}/sendMessage with chat_id and text=message, parse_mode="HTML"
  - try/except: log error, return False on fail, True on success
  - if disabled: return False silently
- notify_signal(symbol, market, signal, action, qty, dry_run):
  - Only send if action is BUY or SELL (skip HOLD)
  - Format:
    [DRY RUN] or [LIVE] prefix
    BUY: "📈 <b>매수 신호</b>\n종목: {symbol} ({market})\n수량: {qty}주\n전략: 모멘텀 MA 크로스오버"
    SELL: "📉 <b>매도 신호</b>\n종목: {symbol} ({market})\n수량: {qty}주\n전략: 모멘텀 MA 크로스오버"
- notify_portfolio(snapshot: dict):
  - Format:
    "📊 <b>포트폴리오 현황</b>\n"
    "총 평가금액: {total_krw:,.0f}원\n"
    "한국주식: {kr_total:,.0f}원\n"
    "미국주식: {us_total_krw:,.0f}원\n"
    "당일 손익: {daily_pnl:+,.0f}원 ({daily_pnl_rate:+.2f}%)\n"
    "누적 손익: {total_pnl:+,.0f}원 ({total_pnl_rate:+.2f}%)\n"
    "업데이트: {timestamp} KST"
  - kr_total = snapshot['kr']['total_eval_amount']
  - us_total_krw = snapshot['us_total_krw']
- notify_error(context: str, error: str):
  - Format: "⚠️ <b>에러 발생</b>\n위치: {context}\n내용: {error}"
- notify_startup():
  - Send: "🤖 <b>투자 봇 시작</b>\n스케줄러가 실행되었습니다.\n- KR 시세 수집: 5분마다\n- US 시세 수집: 5분마다\n- 포트폴리오 스냅샷: 30분마다\n- 매매 신호 체크: 평일 09:05 KST (DRY RUN)"
- notify_shutdown():
  - Send: "🛑 <b>투자 봇 종료</b>\n스케줄러가 정지되었습니다."

## Files to MODIFY

### config/settings.py
Add:
- TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
- TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "")

### .env.example
Add:
- TELEGRAM_BOT_TOKEN=your_telegram_bot_token
- TELEGRAM_CHAT_ID=your_chat_id

### execution/live_runner.py
Modify run_once() to:
- Accept optional notifier: TelegramNotifier = None parameter
- After determining action (BUY/SELL/HOLD), if notifier: call notifier.notify_signal(symbol, market, signal, action, qty, dry_run)

### portfolio/tracker.py
Modify snapshot_and_notify() to:
- Accept optional telegram_notifier: TelegramNotifier = None parameter
- After Notion update, if telegram_notifier: call telegram_notifier.notify_portfolio(snapshot)

### scheduler/runner.py
- Import TelegramNotifier from notify.telegram_notifier
- Create: notifier = TelegramNotifier(settings.TELEGRAM_BOT_TOKEN, settings.TELEGRAM_CHAT_ID)
- Pass notifier to LiveStrategyRunner and PortfolioTracker calls
- On scheduler start: notifier.notify_startup()
- On KeyboardInterrupt/shutdown: notifier.notify_shutdown()
- Wrap existing jobs in try/except: on exception call notifier.notify_error(context, str(exc))

## Constraints
- Use requests (already installed) for Telegram API calls
- TelegramNotifier disabled silently if token/chat_id missing
- Never crash scheduler on Telegram failure
- HTML parse_mode for bold formatting with <b> tags
- snapshot portfolio format: use same field names as existing snapshot dict

## Done Criteria
- python main.py --scheduler sends startup message to Telegram
- 30min portfolio snapshot sends Telegram message
- BUY/SELL signal sends Telegram message (HOLD does not)
- Ctrl+C sends shutdown message
- Error in any job sends error alert
