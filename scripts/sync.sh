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
  local principles_path="$REPO_DIR/SHARED_PRINCIPLES.md"
  local memory_path="$REPO_DIR/SHARED_MEMORY.md"
  local orchestration_setup_path="$REPO_DIR/ORCHESTRATION_SETUP.md"

  # Replace the placeholder sections.
  # macOS /usr/bin/awk (BSD awk) doesn't accept multi-line strings passed via -v,
  # so pass file paths and print file contents from inside awk instead.
  awk -v principles_file="$principles_path" -v memory_file="$memory_path" -v orchestration_setup_file="$orchestration_setup_path" '
    function print_file(f, line) {
      while ((getline line < f) > 0) print line
      close(f)
    }
    /<!-- BEGIN SHARED_PRINCIPLES -->/{
      print
      print_file(principles_file)
      in_block=1
      next
    }
    /<!-- END SHARED_PRINCIPLES -->/{
      in_block=0
      print
      next
    }
    /<!-- BEGIN SHARED_MEMORY -->/{
      print
      print_file(memory_file)
      in_block=1
      next
    }
    /<!-- END SHARED_MEMORY -->/{
      in_block=0
      print
      next
    }
    /<!-- BEGIN ORCHESTRATION_SETUP -->/{
      print
      print_file(orchestration_setup_file)
      in_block=1
      next
    }
    /<!-- END ORCHESTRATION_SETUP -->/{
      in_block=0
      print
      next
    }
    !in_block { print }
  ' "$adapter_file" > "$tmp_file"

  mv "$tmp_file" "$adapter_file"
  echo "[OK] Injected shared content into $(basename "$adapter_file")"
}

# --- Deploy to agent config location ---
deploy_claude() {
  local target_dir="$BASE_DIR/.claude"
  mkdir -p "$target_dir"

  # Deploy orchestrator rules to .claude directory
  cp "$REPO_DIR/adapters/claude.md" "$target_dir/orchestrator_rules.md"
  echo "[OK] Claude adapter → $target_dir/orchestrator_rules.md"

  # Deploy global CLAUDE.md (adapters/claude_global.md가 정본)
  sed "s|~/projects/agent-orchestration|$REPO_DIR|g" "$REPO_DIR/adapters/claude_global.md" > "$BASE_DIR/CLAUDE.md"
  echo "[OK] Global CLAUDE.md → $BASE_DIR/CLAUDE.md"

  # Deploy settings.json (settings 없을 때만 — 기존 설정 덮어쓰지 않음)
  local settings_file="$target_dir/settings.json"
  local template_file="$REPO_DIR/configs/settings_template.json"

  if [ ! -f "$settings_file" ]; then
    cp "$template_file" "$settings_file"
    echo "[OK] Claude settings.json deployed from template → $settings_file"
    echo "[INFO] 전체 배포가 필요하면: bash $REPO_DIR/scripts/deploy-settings.sh"
  elif ! grep -q '"WebSearch"' "$settings_file"; then
    cp "$template_file" "$settings_file"
    echo "[WARN] settings.json missing WebSearch hook — redeployed from template"
  else
    echo "[OK] Claude settings.json up to date"
  fi

  # Deploy notion_db.py to home directory
  cp "$REPO_DIR/scripts/notion_db.py" "$BASE_DIR/notion_db.py"
  echo "[OK] notion_db.py → $BASE_DIR/notion_db.py"

  # Deploy ppt_builder.py to .claude directory
  local claude_dir="$target_dir"
  if [ -f "$REPO_DIR/scripts/ppt_builder.py" ]; then
    cp "$REPO_DIR/scripts/ppt_builder.py" "$claude_dir/ppt_builder.py"
    echo "[OK] ppt_builder.py → $claude_dir/ppt_builder.py"
  fi

  # Deploy session-logger.sh to .claude directory
  if [ -f "$REPO_DIR/scripts/session-logger.sh" ]; then
    cp "$REPO_DIR/scripts/session-logger.sh" "$claude_dir/session-logger.sh"
    chmod +x "$claude_dir/session-logger.sh"
    echo "[OK] session-logger.sh → $claude_dir/session-logger.sh"
  fi

  # Deploy connection layer scripts (save_to_notion.sh, memory_update.sh, chain.sh)
  for script in save_to_notion.sh memory_update.sh chain.sh knowledge_update.sh feedback.sh; do
    if [ -f "$REPO_DIR/scripts/$script" ]; then
      cp "$REPO_DIR/scripts/$script" "$SCRIPT_DIR/$script" || true
      chmod +x "$SCRIPT_DIR/$script"
      echo "[OK] $script (already in scripts/)"
    fi
  done

  # Sync notion_pages.conf (page ID cache) — copy if src newer or dest missing
  local notion_conf_src="$HOME/.config/agent-orchestration/notion_pages.conf"
  local notion_conf_dst="$REPO_DIR/configs/notion_pages.conf"
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

setup_mcp() {
  if [ -n "${GEMINI_API_KEY:-}" ]; then
    bash "$REPO_DIR/configs/mcp_setup.sh"
  else
    echo "[SKIP] MCP setup skipped — set GEMINI_API_KEY to register MCP servers"
    echo "  Run manually: GEMINI_API_KEY=your_key bash configs/mcp_setup.sh"
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

  # MCP setup
  echo ""
  echo "--- MCP Servers ---"
  setup_mcp

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
