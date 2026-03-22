#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
LOG_FILE="$LOG_DIR/topics-bot.log"
BOT_SCRIPT="$SCRIPT_DIR/topics-bot.py"

if [[ -f "$HOME/.zshenv" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.zshenv"
fi

mkdir -p "$LOG_DIR"

if pgrep -f "python3 .*topics-bot.py" >/dev/null 2>&1 || pgrep -f "topics-bot.py" >/dev/null 2>&1; then
  echo "[SKIP] topics-bot already running"
  exit 0
fi

nohup python3 "$BOT_SCRIPT" >>"$LOG_FILE" 2>&1 &
echo "[OK] topics-bot started (pid=$!)"
echo "[LOG] $LOG_FILE"

