#!/usr/bin/env bash
# start-claude-channel.sh — M4에서 claude-channel tmux 세션 안전하게 시작
# 사용: ssh m4 'bash ~/projects/agent-orchestration/scripts/start-claude-channel.sh'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

set -e

SESSION="claude-channel"
LOG="$HOME/Library/Logs/claude-channel.log"
mkdir -p "$(dirname "$LOG")"

# 1. PATH 명시 (bun, nvm, brew)
export PATH="$HOME/.bun/bin:$HOME/.nvm/versions/node/v24.14.0/bin:/opt/homebrew/bin:$PATH"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

# 2. 기존 좀비 프로세스 정리 (polling 충돌 방지)
pkill -9 -f 'bun.*telegram' 2>/dev/null || true
pkill -9 -f 'claude.*channels.*telegram' 2>/dev/null || true
sleep 1

# 3. 기존 tmux 세션 종료
tmux kill-session -t "$SESSION" 2>/dev/null || true

# 4. 의존성 검증
for cmd in tmux bun claude; do
  command -v "$cmd" >/dev/null || { echo "❌ $cmd not found in PATH"; exit 1; }
done

# 5. 플러그인 최신화
claude plugin marketplace update claude-plugins-official 2>&1 | tail -1
claude plugin update telegram@claude-plugins-official 2>&1 | tail -1

# 6. 새 tmux 세션 시작 (detached)
# 주의: claude는 PTY 필요. tee 파이프 거치면 stdin 사라져서 즉시 종료됨.
# 로그는 tmux pipe-pane으로 별도 캡처.
tmux new-session -d -s "$SESSION" \
  "export PATH=\$HOME/.bun/bin:\$HOME/.nvm/versions/node/v24.14.0/bin:/opt/homebrew/bin:\$PATH; \
   export NVM_DIR=\$HOME/.nvm; \
   source \$HOME/.nvm/nvm.sh; \
   exec claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official"

tmux pipe-pane -t "$SESSION" -o "cat >> '$LOG'"

# 7. 검증
sleep 6
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "❌ Failed to start tmux session"
  exit 1
fi

echo "✅ tmux session '$SESSION' running"

if pgrep -f "bun.*telegram" >/dev/null; then
  echo "✅ telegram MCP server running"
else
  echo "⚠️  telegram MCP not detected yet (may take a moment to start)"
fi

echo ""
echo "Attach: ssh m4 -t 'tmux attach -t $SESSION'"
echo "Detach: Ctrl+B then D"
echo "Logs:   $LOG"
