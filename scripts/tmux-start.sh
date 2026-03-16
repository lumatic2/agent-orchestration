#!/usr/bin/env bash
# tmux-start.sh — 작업 세션 자동 구성
#
# 사용법:
#   bash ~/projects/agent-orchestration/scripts/tmux-start.sh
#   또는 alias: ws (work sessions)
#
# 세션 구성:
#   claude  → Claude Code 메인 작업
#   codex   → Codex Brain / 코드 작업
#   monitor → 로그 모니터링 (content-automation, launchd)
#   remote  → m1 SSH 상시 접속

set -euo pipefail

PROJECT="$HOME/projects/agent-orchestration"

start_session() {
  local name="$1"
  local dir="${2:-$HOME}"

  if tmux has-session -t "$name" 2>/dev/null; then
    echo "[SKIP] 세션 '$name' 이미 존재"
    return
  fi

  tmux new-session -d -s "$name" -c "$dir"
  echo "[OK] 세션 '$name' 생성 ($dir)"
}

# ── 세션 생성 ────────────────────────────────────────────────

# 1. claude — Claude Code 메인
start_session "claude" "$PROJECT"
tmux send-keys -t "claude" "# Claude Code 세션. 시작: claude" Enter

# 2. codex — Codex Brain
start_session "codex" "$PROJECT"
tmux send-keys -t "codex" "# Codex Brain 세션. 시작: codex-brain '요청'" Enter

# 3. monitor — 로그 모니터링 (2분할)
start_session "monitor" "$HOME/projects/content-automation"
tmux split-window -t "monitor" -v -c "$PROJECT/logs"
tmux send-keys -t "monitor:1.1" "# content-automation 로그: tail -f ~/projects/content-automation/logs/*.log" Enter
tmux send-keys -t "monitor:1.2" "# orchestration 로그: tail -f $PROJECT/logs/bash_audit.log" Enter
tmux select-pane -t "monitor:1.1"

# 4. remote — m1 SSH
start_session "remote" "$HOME"
tmux send-keys -t "remote" "ssh m1" Enter

# ── 완료 ─────────────────────────────────────────────────────

echo ""
echo "세션 목록:"
tmux ls

echo ""
echo "전환 방법:"
echo "  Ctrl+a s    → 세션 목록 (트리뷰)"
echo "  Ctrl+a \$    → 세션 이름 변경"
echo "  Ctrl+a d    → 분리 (세션 백그라운드 유지)"
echo ""
echo "claude 세션으로 이동:"
tmux attach-session -t "claude"
