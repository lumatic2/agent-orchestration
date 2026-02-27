#!/usr/bin/env bash
# ============================================================
# sync.sh — Deploy shared files to each agent's config format
#
# What it does:
#   1. Detects OS (Windows / macOS)
#   2. Reads SHARED_PRINCIPLES.md + SHARED_MEMORY.md
#   3. Injects them into each adapter (claude.md, codex.md, gemini.md)
#   4. Copies adapters to each agent's expected config location
#   5. Verifies each agent CLI is installed and compatible
#
# Usage:
#   bash sync.sh              (sync all)
#   bash sync.sh --check      (verify only, no writes)
#   bash sync.sh --agent codex (sync specific agent)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# --- OS Detection ---
detect_os() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      OS="windows"
      BASE_DIR="/c/Users/1"
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

# --- Inject shared content into adapter ---
inject_shared() {
  local adapter_file="$1"
  local tmp_file="${adapter_file}.tmp"
  local principles_content
  local memory_content

  principles_content=$(cat "$REPO_DIR/SHARED_PRINCIPLES.md")
  memory_content=$(cat "$REPO_DIR/SHARED_MEMORY.md")

  # Replace the placeholder sections
  awk -v principles="$principles_content" -v memory="$memory_content" '
    /<!-- BEGIN SHARED_PRINCIPLES -->/{
      print $0
      print principles
      skip=1; next
    }
    /<!-- END SHARED_PRINCIPLES -->/{
      print $0
      skip=0; next
    }
    /<!-- BEGIN SHARED_MEMORY -->/{
      print $0
      print memory
      skip=1; next
    }
    /<!-- END SHARED_MEMORY -->/{
      print $0
      skip=0; next
    }
    !skip { print }
  ' "$adapter_file" > "$tmp_file"

  mv "$tmp_file" "$adapter_file"
  echo "[OK] Injected shared content into $(basename "$adapter_file")"
}

# --- Deploy to agent config location ---
deploy_claude() {
  local target_dir="$BASE_DIR/.claude"
  mkdir -p "$target_dir"

  # Deploy as CLAUDE.md in the user's .claude directory
  cp "$REPO_DIR/adapters/claude.md" "$target_dir/orchestrator_rules.md"
  echo "[OK] Claude adapter → $target_dir/orchestrator_rules.md"

  # Deploy guard.sh hook config
  local settings_file="$target_dir/settings.json"
  local guard_path="$REPO_DIR/scripts/guard.sh"

  if [ ! -f "$settings_file" ]; then
    cat > "$settings_file" << SETTINGS_EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "command": "bash $guard_path \"\$TOOL_INPUT\""
      }
    ]
  }
}
SETTINGS_EOF
    echo "[OK] Created Claude settings.json with guard hook"
  else
    echo "[SKIP] Claude settings.json already exists — verify guard hook manually"
  fi
}

deploy_codex() {
  # Codex reads AGENTS.md from project root.
  # We deploy to a global location; user symlinks per project.
  local target_dir="$BASE_DIR/.codex"
  mkdir -p "$target_dir"
  cp "$REPO_DIR/adapters/codex.md" "$target_dir/AGENTS.md"
  echo "[OK] Codex adapter → $target_dir/AGENTS.md"
  echo "[NOTE] Symlink to project roots: ln -s $target_dir/AGENTS.md /path/to/project/AGENTS.md"
}

deploy_gemini() {
  # Gemini reads GEMINI.md from project root or ~/.gemini/GEMINI.md
  local target_dir="$BASE_DIR/.gemini"
  mkdir -p "$target_dir"
  cp "$REPO_DIR/adapters/gemini.md" "$target_dir/GEMINI.md"
  echo "[OK] Gemini adapter → $target_dir/GEMINI.md"
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

  if [ "$mode" = "--check" ]; then
    echo ""
    echo "[DONE] Check complete. No files modified."
    exit 0
  fi

  # Inject shared content into adapters (work on copies)
  echo ""
  echo "--- Injecting Shared Content ---"
  # Work on copies to keep originals clean
  cp "$REPO_DIR/adapters/claude.md" "$REPO_DIR/adapters/claude.md.build"
  cp "$REPO_DIR/adapters/codex.md" "$REPO_DIR/adapters/codex.md.build"
  cp "$REPO_DIR/adapters/gemini.md" "$REPO_DIR/adapters/gemini.md.build"

  inject_shared "$REPO_DIR/adapters/claude.md.build"
  inject_shared "$REPO_DIR/adapters/codex.md.build"
  inject_shared "$REPO_DIR/adapters/gemini.md.build"

  # Swap build files into adapters for deployment
  mv "$REPO_DIR/adapters/claude.md.build" "$REPO_DIR/adapters/claude.md.deploy"
  mv "$REPO_DIR/adapters/codex.md.build" "$REPO_DIR/adapters/codex.md.deploy"
  mv "$REPO_DIR/adapters/gemini.md.build" "$REPO_DIR/adapters/gemini.md.deploy"

  # Deploy
  echo ""
  echo "--- Deploying ---"

  # Temporarily swap deploy files for deployment
  local claude_orig="$REPO_DIR/adapters/claude.md"
  local codex_orig="$REPO_DIR/adapters/codex.md"
  local gemini_orig="$REPO_DIR/adapters/gemini.md"

  cp "$REPO_DIR/adapters/claude.md.deploy" "$claude_orig.bak"
  cp "$REPO_DIR/adapters/codex.md.deploy" "$codex_orig.bak"
  cp "$REPO_DIR/adapters/gemini.md.deploy" "$gemini_orig.bak"

  # Use deploy versions for actual deployment
  if [ "$target_agent" = "all" ] || [ "$target_agent" = "claude" ]; then
    cp "$REPO_DIR/adapters/claude.md.deploy" "$REPO_DIR/adapters/claude.md"
    deploy_claude
    cp "$claude_orig.bak" "$REPO_DIR/adapters/claude.md" 2>/dev/null || true
  fi

  if [ "$target_agent" = "all" ] || [ "$target_agent" = "codex" ]; then
    cp "$REPO_DIR/adapters/codex.md.deploy" "$REPO_DIR/adapters/codex.md"
    deploy_codex
    cp "$codex_orig.bak" "$REPO_DIR/adapters/codex.md" 2>/dev/null || true
  fi

  if [ "$target_agent" = "all" ] || [ "$target_agent" = "gemini" ]; then
    cp "$REPO_DIR/adapters/gemini.md.deploy" "$REPO_DIR/adapters/gemini.md"
    deploy_gemini
    cp "$gemini_orig.bak" "$REPO_DIR/adapters/gemini.md" 2>/dev/null || true
  fi

  # Cleanup
  rm -f "$REPO_DIR/adapters/"*.deploy "$REPO_DIR/adapters/"*.bak

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
