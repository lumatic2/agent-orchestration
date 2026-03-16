#!/usr/bin/env bash
# deploy-settings.sh — ~/.claude/ 설정을 전체 기기에 배포
#
# 사용법:
#   bash scripts/deploy-settings.sh          # 전체 배포
#   bash scripts/deploy-settings.sh local    # 현재 기기만
#   bash scripts/deploy-settings.sh mac      # Mac 3대만
#   bash scripts/deploy-settings.sh windows  # Windows만

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$REPO_DIR/config"
TARGET="${1:-all}"

deploy_mac() {
  local host="$1"
  local label="$2"
  if [ "$host" = "local" ]; then
    cp "$CONFIG_DIR/mac-settings.json" ~/.claude/settings.json
    cp "$CONFIG_DIR/CLAUDE.md" ~/.claude/CLAUDE.md
    cp "$REPO_DIR/.git/hooks/pre-commit" ~/.claude/../ 2>/dev/null || true
    echo "  ✓ $label (local)"
  else
    scp "$CONFIG_DIR/mac-settings.json" "$host:~/.claude/settings.json"
    scp "$CONFIG_DIR/CLAUDE.md" "$host:~/.claude/CLAUDE.md"
    # pre-commit hook
    ssh "$host" "mkdir -p ~/projects/agent-orchestration/.git/hooks"
    scp "$REPO_DIR/.git/hooks/pre-commit" "$host:~/projects/agent-orchestration/.git/hooks/pre-commit"
    ssh "$host" "chmod +x ~/projects/agent-orchestration/.git/hooks/pre-commit"
    echo "  ✓ $label ($host)"
  fi
}

deploy_windows() {
  scp "$CONFIG_DIR/windows-settings.json" 'windows:C:\Users\1\.claude\settings.json'
  scp "$CONFIG_DIR/CLAUDE.md" 'windows:C:\Users\1\.claude\CLAUDE.md'
  echo "  ✓ Windows"
}

echo "[deploy-settings] 시작: target=$TARGET"

case "$TARGET" in
  local)
    deploy_mac local "Mac Air"
    ;;
  mac)
    deploy_mac local "Mac Air"
    deploy_mac m1 "Mac mini" &
    deploy_mac m4 "M4" &
    wait
    ;;
  windows)
    deploy_windows
    ;;
  all)
    deploy_mac local "Mac Air"
    deploy_mac m1 "Mac mini" &
    deploy_mac m4 "M4" &
    deploy_windows &
    wait
    ;;
  *)
    echo "Usage: $0 [all|local|mac|windows]" >&2
    exit 1
    ;;
esac

echo "[deploy-settings] 완료"
