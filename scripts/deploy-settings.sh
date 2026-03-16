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
    cp "$REPO_DIR/.githooks/pre-commit" "$REPO_DIR/.git/hooks/pre-commit" 2>/dev/null || true
    chmod +x "$REPO_DIR/.git/hooks/pre-commit" 2>/dev/null || true
    echo "  ✓ $label (local)"
  else
    scp "$CONFIG_DIR/mac-settings.json" "$host:~/.claude/settings.json"
    scp "$CONFIG_DIR/CLAUDE.md" "$host:~/.claude/CLAUDE.md"
    ssh "$host" "mkdir -p ~/projects/agent-orchestration/.git/hooks"
    scp "$REPO_DIR/.githooks/pre-commit" "$host:~/projects/agent-orchestration/.git/hooks/pre-commit"
    ssh "$host" "chmod +x ~/projects/agent-orchestration/.git/hooks/pre-commit"
    echo "  ✓ $label ($host)"
  fi
}

deploy_windows() {
  scp "$CONFIG_DIR/windows-settings.json" 'windows:C:\Users\1\.claude\settings.json'
  scp "$CONFIG_DIR/CLAUDE.md" 'windows:C:\Users\1\.claude\CLAUDE.md'
  ssh windows "mkdir -p ~/projects/agent-orchestration/.git/hooks" 2>/dev/null || true
  scp "$REPO_DIR/.githooks/pre-commit" "windows:~/projects/agent-orchestration/.git/hooks/pre-commit" 2>/dev/null || true
  echo "  ✓ Windows"
}

deploy_codex_brain_alias() {
  local host="$1"
  # heredoc 방식으로 작성 (single quote 충돌 방지)
  local alias_snippet
  alias_snippet=$(cat << 'ALIAS'

# Codex Brain 모드 (agent-orchestration)
codex-brain() {
  local request="${*:-대기 중인 태스크 처리}"
  codex "$(cat ~/.codex/CODEX_BRAIN.md)

사용자 요청: $request"
}
ALIAS
)
  if [ "$host" = "local" ]; then
    if ! grep -q "codex-brain" ~/.zshrc 2>/dev/null; then
      echo "$alias_snippet" >> ~/.zshrc
      echo "  ✓ codex-brain alias → ~/.zshrc (local)"
    else
      echo "  ✓ codex-brain alias already in ~/.zshrc (local)"
    fi
  else
    ssh "$host" "grep -q 'codex-brain' ~/.zshrc 2>/dev/null || cat >> ~/.zshrc << 'ALIAS'
$alias_snippet
ALIAS"
    echo "  ✓ codex-brain alias → $host:~/.zshrc"
    scp "$REPO_DIR/configs/codex_mcp_setup.sh" "$host:~/projects/agent-orchestration/configs/codex_mcp_setup.sh" 2>/dev/null || true
    echo "  ✓ codex_mcp_setup.sh → $host"
  fi
}

echo "[deploy-settings] 시작: target=$TARGET"

case "$TARGET" in
  local)
    deploy_mac local "Mac Air"
    deploy_codex_brain_alias local
    ;;
  mac)
    deploy_mac local "Mac Air"
    deploy_codex_brain_alias local
    deploy_mac m1 "Mac mini" &
    deploy_mac m4 "M4" &
    wait
    deploy_codex_brain_alias m1
    deploy_codex_brain_alias m4
    ;;
  windows)
    deploy_windows
    ;;
  all)
    deploy_mac local "Mac Air"
    deploy_codex_brain_alias local
    deploy_mac m1 "Mac mini" &
    deploy_mac m4 "M4" &
    deploy_windows &
    wait
    deploy_codex_brain_alias m1
    deploy_codex_brain_alias m4
    ;;
  *)
    echo "Usage: $0 [all|local|mac|windows]" >&2
    exit 1
    ;;
esac

echo "[deploy-settings] 완료"
