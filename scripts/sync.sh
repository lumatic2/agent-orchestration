#!/usr/bin/env bash
# ============================================================
# sync.sh — Deploy adapters to each agent's config format
#
# What it does:
#   1. Detects OS (Windows / macOS)
#   2. Copies adapters as-is to each agent's expected config location
#   3. Verifies each agent CLI is installed and compatible
#
# Usage:
#   bash sync.sh              (sync all)
#   bash sync.sh --check      (verify only, no writes)
#   bash sync.sh --agent codex (sync specific agent)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# --- OS Detection ---
detect_os() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      OS="windows"
      BASE_DIR="$HOME"
      ;;
    Darwin)
      OS="macos"
      BASE_DIR="$HOME"
      ;;
    Linux)
      OS="linux"
      BASE_DIR="$HOME"
      ;;
    *)
      echo "[ERROR] Unsupported OS: $(uname -s)"
      exit 1
      ;;
  esac
  echo "[INFO] OS detected: $OS (base: $BASE_DIR)"
}

# --- Version Check ---
check_agent() {
  local agent="$1"
  if command -v "$agent" &>/dev/null; then
    local version
    version=$("$agent" --version 2>/dev/null | head -1 || echo "unknown")
    echo "[OK] $agent installed: $version"
    return 0
  else
    echo "[WARN] $agent not found in PATH"
    return 1
  fi
}

# --- Deploy to agent config location ---
deploy_claude() {
  local target_dir="$BASE_DIR/.claude"
  local claude_md_path="$BASE_DIR/CLAUDE.md"
  mkdir -p "$target_dir"

  # Deploy global CLAUDE.md = claude_global.md + USER_CONTEXT.md (concatenated)
  cat "$REPO_DIR/adapters/claude_global.md" "$REPO_DIR/USER_CONTEXT.md" > "$claude_md_path"
  echo "[OK] Global CLAUDE.md → $claude_md_path (with USER_CONTEXT)"

  # Deploy settings.json
  # - 없을 때: settings_common.json (크로스플랫폼) 으로 초기화
  # - 있을 때: patch_hooks.py로 공통 훅만 최신화 (기기별 설정 보존)
  # - NEVER overwrite via SCP (nah_guard 등 기기 전용 항목 손실 위험)
  local settings_file="$target_dir/settings.json"
  local common_file="$REPO_DIR/config/settings_common.json"

  if [ ! -f "$settings_file" ]; then
    cp "$common_file" "$settings_file"
    echo "[OK] Claude settings.json 초기화 (settings_common.json 기반) → $settings_file"
  else
    python3 "$REPO_DIR/scripts/patch_hooks.py" "$settings_file" 2>/dev/null \
      && echo "[OK] settings.json 공통 훅 최신화 (기기별 설정 보존)" \
      || echo "[WARN] settings.json patch 실패"
  fi

  # Deploy notion_db.py to home directory
  cp "$REPO_DIR/scripts/notion_db.py" "$BASE_DIR/notion_db.py"
  echo "[OK] notion_db.py → $BASE_DIR/notion_db.py"

  local claude_dir="$target_dir"

  # Deploy hook scripts to .claude/hooks directory
  local claude_hooks_dir="$claude_dir/hooks"
  mkdir -p "$claude_hooks_dir"
  if [ -d "$REPO_DIR/scripts/hooks" ]; then
    for hook in "$REPO_DIR/scripts/hooks"/*.py "$REPO_DIR/scripts/hooks"/*.sh; do
      [ -f "$hook" ] || continue
      local hook_name
      hook_name="$(basename "$hook")"
      cp "$hook" "$claude_hooks_dir/$hook_name"
      [[ "$hook_name" == *.sh ]] && chmod +x "$claude_hooks_dir/$hook_name"
      echo "[OK] hook → $claude_hooks_dir/$hook_name"
    done
  fi

  # Auto-deploy machine-independent device files (path-free runtime scripts).
  # codex-wrapper / *.plist는 절대경로·플랫폼 의존성이 강해 README 수동 가이드.
  local device_dir="$REPO_DIR/scripts/device"
  local device_auto_files=("job-watcher.mjs" "job-watcher-inject.py")
  local watcher_changed=0
  for f in "${device_auto_files[@]}"; do
    local src="$device_dir/$f"
    local dst="$claude_hooks_dir/$f"
    [ -f "$src" ] || continue
    if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
      cp "$src" "$dst"
      echo "[OK] device hook → $dst"
      [[ "$f" == "job-watcher.mjs" ]] && watcher_changed=1
    fi
  done
  if [ "$watcher_changed" = "1" ]; then
    echo "[NOTE] job-watcher.mjs 코드가 갱신됨. 적용하려면 데몬 재시작:"
    echo "       kill \$(cat ~/.claude/hooks/.job-watcher.pid 2>/dev/null) 2>/dev/null;" \
         "node ~/.claude/hooks/job-watcher.mjs --detach"
  fi

  # 커스텀 스킬은 ~/projects/custom-skills/ 레포에서 관리 (2026-03-29 이전)
  # 배포: bash ~/projects/custom-skills/setup.sh

  # Patch settings.json common hooks (pre-pull scope, push failure detection)
  local settings_file="$target_dir/settings.json"
  if [ -f "$settings_file" ] && command -v python3 &>/dev/null; then
    python3 "$REPO_DIR/scripts/patch_hooks.py" "$settings_file" 2>/dev/null \
      && echo "[OK] settings.json hooks 최신화" \
      || echo "[WARN] settings.json hooks 패치 실패"
  fi

  # Deploy statusline.sh
  cp "$REPO_DIR/config/statusline.sh" "$target_dir/statusline.sh"
  echo "[OK] statusline.sh → $target_dir/statusline.sh"

  # Connection layer scripts already live in scripts/ — no extra deploy needed.

  # Sync notion_pages.conf (page ID cache) — copy if src newer or dest missing
  local notion_conf_src="$HOME/.config/agent-orchestration/notion_pages.conf"
  local notion_conf_dst="$REPO_DIR/config/notion_pages.conf"
  if [ -f "$notion_conf_src" ]; then
    cp "$notion_conf_src" "$notion_conf_dst"
    echo "[OK] notion_pages.conf → $notion_conf_dst (for cross-device sync)"
  fi
  # On Windows or fresh device: restore from repo if local conf is missing
  if [ ! -f "$notion_conf_src" ] && [ -f "$notion_conf_dst" ]; then
    mkdir -p "$(dirname "$notion_conf_src")"
    cp "$notion_conf_dst" "$notion_conf_src"
    echo "[OK] notion_pages.conf ← $notion_conf_dst (restored from repo)"
  fi

}

deploy_codex_home() {
  # Codex reads ~/AGENTS.md globally at session start (home-scope).
  # ~/AGENTS.md = codex_home.md + USER_CONTEXT.md (concatenated) + Custom Commands index.
  local target_path="$BASE_DIR/AGENTS.md"
  if [ -f "$target_path" ] && [ ! -f "$target_path.bak" ]; then
    cp "$target_path" "$target_path.bak"
    echo "[OK] Backed up existing ~/AGENTS.md → ~/AGENTS.md.bak"
  fi
  cat "$REPO_DIR/adapters/codex_home.md" "$REPO_DIR/USER_CONTEXT.md" > "$target_path"
  echo "[OK] Codex home adapter → $target_path (with USER_CONTEXT)"

  # Custom Commands 인덱스 + 공유 스킬 본문 동기화 (~/AGENTS.md 끝에 append)
  bash "$REPO_DIR/scripts/sync-codex-skills.sh" "$target_path"
}

# Migrate legacy project-scope Codex config (~/.codex/AGENTS.md + project symlinks).
# Idempotent — safe to run on devices that already migrated or never had legacy state.
migrate_codex_legacy() {
  local legacy_agents="$BASE_DIR/.codex/AGENTS.md"
  local cleaned=0

  if [ -f "$legacy_agents" ]; then
    rm -f "$legacy_agents"
    echo "[MIGRATE] Removed legacy $legacy_agents (now superseded by ~/AGENTS.md)"
    cleaned=1
  fi
  # Note: ~/.codex/skills/ is NOT legacy — it's still where shared skill bodies live.
  # Only the AGENTS.md location moved (project-scope → ~/AGENTS.md).

  # Find and remove project AGENTS.md symlinks pointing at the legacy file
  if [ -d "$BASE_DIR/projects" ]; then
    while IFS= read -r link; do
      local target
      target="$(readlink "$link" 2>/dev/null || true)"
      case "$target" in
        *.codex/AGENTS.md|*"/.codex/AGENTS.md")
          rm -f "$link"
          echo "[MIGRATE] Removed stale symlink $link → $target"
          cleaned=1
          ;;
      esac
    done < <(find "$BASE_DIR/projects" -maxdepth 3 -name AGENTS.md -type l 2>/dev/null)
  fi

  [ "$cleaned" = "0" ] && return 0 || return 0
}

deploy_gemini() {
  # Gemini reads GEMINI.md from project root or ~/.gemini/GEMINI.md
  local target_dir="$BASE_DIR/.gemini"
  mkdir -p "$target_dir"
  cp "$REPO_DIR/adapters/gemini.md" "$target_dir/GEMINI.md"
  echo "[OK] Gemini adapter → $target_dir/GEMINI.md"
}


deploy_codex_main() {
  local dest_agents="$HOME/projects/agent-orchestration-Codex_main/AGENTS.md"
  local src="$REPO_DIR/../agent-orchestration-Codex_main/adapters/codex_global.md"
  if [ -f "$src" ]; then
    cp "$src" "$dest_agents"
    echo "[OK] codex_main AGENTS.md deployed"
  else
    echo "[WARN] codex_global.md not found, skipping codex_main deploy"
  fi
}

setup_mcp() {
  if [ -n "${GEMINI_API_KEY:-}" ]; then
    bash "$REPO_DIR/config/mcp_setup.sh"
  else
    echo "[SKIP] MCP setup skipped — set GEMINI_API_KEY to register MCP servers"
    echo "  Run manually: GEMINI_API_KEY=your_key bash config/mcp_setup.sh"
  fi
}

# --- Main ---
main() {
  local mode="${1:-sync}"
  local target_agent="${2:-all}"

  echo "========================================"
  echo " Agent Orchestration Sync"
  echo "========================================"

  detect_os

  # Version checks
  echo ""
  echo "--- Agent Status ---"
  check_agent "claude" || true
  check_agent "codex" || true
  check_agent "gemini" || true

  # Ensure PyYAML is installed (required for agent_config.yaml parsing)
  if ! python3 -c "import yaml" 2>/dev/null; then
    echo "[FIX] PyYAML not found — installing..."
    pip3 install pyyaml --quiet 2>/dev/null || python3 -m pip install pyyaml --quiet 2>/dev/null || true
    if python3 -c "import yaml" 2>/dev/null; then
      echo "[OK] PyYAML installed"
    else
      echo "[WARN] PyYAML install failed — complexity routing will use builtin defaults"
    fi
  else
    echo "[OK] PyYAML available"
  fi

  if [ "$mode" = "--check" ]; then
    echo ""
    echo "[DONE] Check complete. No files modified."
    exit 0
  fi

  # Deploy
  echo ""
  echo "--- Deploying ---"

  if [ "$target_agent" = "all" ] || [ "$target_agent" = "claude" ]; then
    deploy_claude
  fi

  if [ "$target_agent" = "all" ] || [ "$target_agent" = "codex" ]; then
    migrate_codex_legacy
    deploy_codex_home
  fi

  if [ "$target_agent" = "all" ] || [ "$target_agent" = "gemini" ]; then
    deploy_gemini
  fi

  deploy_codex_main

  # MCP setup
  echo ""
  echo "--- MCP Servers ---"
  setup_mcp
  python3 "$REPO_DIR/scripts/check_mcp.py" 2>/dev/null || true

  # --- Line Budget Check ---
  echo ""
  echo "--- Line Budget Check ---"
  check_budget() {
    local file="$1" budget="$2" label="$3"
    if [ -f "$file" ]; then
      local lines
      lines=$(wc -l < "$file" | tr -d ' ')
      if [ "$lines" -gt "$budget" ]; then
        echo "[WARN] $label exceeds budget ($lines/$budget lines)"
      else
        echo "[OK]   $label ($lines/$budget lines)"
      fi
    fi
  }
  # Check deployed files
  check_budget "$BASE_DIR/CLAUDE.md" 160 "~/CLAUDE.md"
  check_budget "$BASE_DIR/AGENTS.md" 120 "~/AGENTS.md (Codex home)"
  check_budget "$BASE_DIR/.gemini/GEMINI.md" 150 "GEMINI.md"

  echo ""
  echo "========================================"
  echo " Sync complete!"
  echo "========================================"
}

# Parse args
case "${1:-}" in
  --check)
    main "--check"
    ;;
  --agent)
    main "sync" "${2:-all}"
    ;;
  *)
    main "sync" "all"
    ;;
esac
