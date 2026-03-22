#!/bin/zsh
# telegram-daemon-watch.sh
# VS Code Claude 세션이 없을 때 telegram 데몬을 자동으로 재시작한다.

PLIST="$HOME/Library/LaunchAgents/com.claude.telegram-channel.plist"
[ -f "$PLIST" ] || exit 0

# VS Code Claude 실행 여부 (native-binary 경로로 구분)
VSCODE_COUNT=$(ps -ax -o args 2>/dev/null | grep -c "native-binary/claude" || echo 0)

# 데몬 실행 여부
DAEMON_PID=$(launchctl list com.claude.telegram-channel 2>/dev/null | grep '"PID" =' | grep -v '"PID" = -1' | wc -l | tr -d ' ')

if [ "$VSCODE_COUNT" -gt 0 ]; then
  # VS Code 활성 → 데몬이 켜져 있으면 끔
  if [ "$DAEMON_PID" -gt 0 ]; then
    launchctl unload "$PLIST" 2>/dev/null
  fi
else
  # VS Code 없음 → 데몬이 꺼져 있으면 켬
  if [ "$DAEMON_PID" -eq 0 ]; then
    launchctl load "$PLIST" 2>/dev/null
  fi
fi
