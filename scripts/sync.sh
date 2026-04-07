#!/usr/bin/env bash
# ============================================================
# sync.sh — Deploy shared files to each agent's config format
#
# What it does:
#   1. Detects OS (Windows / macOS)
#   2. Reads SHARED_PRINCIPLES.md
#   3. Injects into each adapter (claude.md, codex.md, gemini.md)
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
source "$SCRIPT_DIR/env.sh"
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

  # Replace the placeholder sections.
  # macOS /usr/bin/awk (BSD awk) doesn't accept multi-line strings passed via -v,
  # so pass file paths and print file contents from inside awk instead.
  awk -v principles_file="$principles_path" '
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
    !in_block { print }
  ' "$adapter_file" > "$tmp_file"

  mv "$tmp_file" "$adapter_file"
  echo "[OK] Injected shared content into $(basename "$adapter_file")"
}

resolve_active_mode() {
  local active_mode_src="$REPO_DIR/queue/.active_mode"
  local active_mode_dst="$HOME/.config/agent-orchestration/.active_mode"
  local active_mode=""

  if [ -f "$active_mode_src" ]; then
    active_mode="$(head -n 1 "$active_mode_src" | tr -d '[:space:]')"
  fi

  if [ -z "$active_mode" ] && [ -f "$active_mode_dst" ]; then
    active_mode="$(head -n 1 "$active_mode_dst" | tr -d '[:space:]')"
  fi

  if [ -z "$active_mode" ]; then
    active_mode="$(python3 - "$REPO_DIR/agent_config.yaml" <<'PY'
import sys
try:
  import yaml
except Exception:
  yaml = None

if yaml is None:
  print("full")
  raise SystemExit

try:
  with open(sys.argv[1], "r", encoding="utf-8") as f:
    cfg = yaml.safe_load(f) or {}
except Exception:
  cfg = {}

default_mode = cfg.get("default_mode", "full")
print(default_mode if isinstance(default_mode, str) and default_mode else "full")
PY
)"
  fi

  echo "${active_mode:-full}"
}

read_mode_guard() {
  local requested_mode="$1"
  python3 - "$REPO_DIR/agent_config.yaml" "$requested_mode" <<'PY'
import sys
try:
  import yaml
except Exception:
  yaml = None

cfg = {}
if yaml is not None:
  try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
      cfg = yaml.safe_load(f) or {}
  except Exception:
    cfg = {}

requested_mode = sys.argv[2].strip()
modes = cfg.get("modes", {}) if isinstance(cfg, dict) else {}
default_mode = cfg.get("default_mode", "full") if isinstance(cfg, dict) else "full"
mode = requested_mode if requested_mode in modes else default_mode
if mode not in modes:
  mode = "full"

mode_cfg = modes.get(mode, {})
guard = mode_cfg.get("guard", {}) if isinstance(mode_cfg, dict) else {}
if not isinstance(guard, dict):
  guard = {}

max_lines = guard.get("max_lines_claude", 50)
max_files = guard.get("max_files_claude", 3)
research_delegate = bool(guard.get("research_delegate", True))

print(mode)
print(max_lines)
print(max_files)
print("true" if research_delegate else "false")
PY
}

build_guard_table() {
  local mode_name="$1"
  local max_lines="$2"
  local max_files="$3"
  local research_delegate="$4"

  local codex_cmd='`orchestrate.sh codex "task" name`'
  local gemini_cmd='`orchestrate.sh gemini "task" name`'
  local chatgpt_cmd='`orchestrate.sh chatgpt "task" name`'
  local openclaw_cmd='`orchestrate.sh openclaw "task" name`'

  local cond_lines="${max_lines}+ lines of code to write"
  local cond_files="${max_files}+ files to create/modify"
  local action_lines="STOP → ${codex_cmd}"
  local action_files="STOP → ${codex_cmd}"
  local action_research="STOP → ${gemini_cmd}"
  local action_browser="STOP → ${openclaw_cmd}"
  local action_simple="Proceed directly"

  case "$mode_name" in
    solo)
      cond_lines="No code-size limit"
      cond_files="No file-count limit"
      action_lines="Proceed directly (solo mode)"
      action_files="Proceed directly (solo mode)"
      action_research="Proceed directly (solo mode)"
      action_browser="Proceed directly (solo mode)"
      ;;
    research)
      action_lines="STOP → ${codex_cmd} (ultra only)"
      action_files="STOP → ${codex_cmd} (ultra only)"
      ;;
    code)
      action_research="Light/default: Proceed directly; Heavy: STOP → ${gemini_cmd}"
      ;;
    conserve-gemini)
      action_research="Light/default: STOP → ${chatgpt_cmd}; Heavy: STOP → ${gemini_cmd}"
      ;;
    conserve-codex)
      action_lines="STOP → ${codex_cmd} (high/ultra only)"
      action_files="STOP → ${codex_cmd} (high/ultra only)"
      ;;
    *)
      if [ "$research_delegate" != "true" ]; then
        action_research="Proceed directly"
      fi
      ;;
  esac

  if [ "$research_delegate" != "true" ] && [ "$mode_name" != "solo" ]; then
    action_research="Proceed directly"
  fi

  cat <<EOF
> 현재 모드: ${mode_name}

| Condition | Action |
|---|---|
| ${cond_lines} | ${action_lines} |
| ${cond_files} | ${action_files} |
| Complex research (4+ sources, trend, crawl, 50p+ doc) | ${action_research} |
| Browser/GUI/canvas/JS SPA needed | ${action_browser} |
| Simple research (≤3 searches, single topic) | Proceed directly (WebSearch/WebFetch) |
| Simple edit (1-${max_files} files, <${max_lines} lines) | ${action_simple} |
EOF
}

render_claude_global() {
  local output_path="$1"
  local mode_name="$2"
  local max_lines="$3"
  local max_files="$4"
  local research_delegate="$5"
  local template_path="$REPO_DIR/adapters/claude_global.md"
  local guard_table_file
  guard_table_file="$(mktemp)"

  build_guard_table "$mode_name" "$max_lines" "$max_files" "$research_delegate" > "$guard_table_file"

  if ! grep -q "<!-- BEGIN GUARD_TABLE -->" "$template_path"; then
    cp "$template_path" "$output_path"
    rm -f "$guard_table_file"
    return 0
  fi

  awk -v guard_file="$guard_table_file" '
    function print_file(f, line) {
      while ((getline line < f) > 0) print line
      close(f)
    }
    /<!-- BEGIN GUARD_TABLE -->/{
      print
      print_file(guard_file)
      in_block=1
      next
    }
    /<!-- END GUARD_TABLE -->/{
      in_block=0
      print
      next
    }
    !in_block { print }
  ' "$template_path" > "$output_path"

  rm -f "$guard_table_file"
}

# --- Deploy to agent config location ---
deploy_claude() {
  local target_dir="$BASE_DIR/.claude"
  local claude_md_path="$BASE_DIR/CLAUDE.md"
  mkdir -p "$target_dir"

  # Deploy orchestrator rules to .claude directory
  cp "$REPO_DIR/adapters/claude.md" "$target_dir/orchestrator_rules.md"
  echo "[OK] Claude adapter → $target_dir/orchestrator_rules.md"

  # Deploy global CLAUDE.md with active mode guard table injection
  local active_mode
  active_mode="$(resolve_active_mode)"
  local guard_output
  guard_output="$(read_mode_guard "$active_mode")"
  local mode_name max_lines max_files research_delegate
  mode_name="$(echo "$guard_output" | sed -n '1p' | tr -d '\r\n[:space:]')"
  max_lines="$(echo "$guard_output" | sed -n '2p' | tr -d '\r\n[:space:]')"
  max_files="$(echo "$guard_output" | sed -n '3p' | tr -d '\r\n[:space:]')"
  research_delegate="$(echo "$guard_output" | sed -n '4p' | tr -d '\r\n[:space:]' | tr '[:upper:]' '[:lower:]')"
  mode_name="${mode_name:-full}"
  max_lines="${max_lines:-50}"
  max_files="${max_files:-3}"
  research_delegate="${research_delegate:-true}"
  render_claude_global "$claude_md_path" "$mode_name" "$max_lines" "$max_files" "$research_delegate"
  echo "[OK] Global CLAUDE.md → $claude_md_path (mode: $mode_name)"

  # Deploy settings.json
  # - 없을 때: settings_common.json (크로스플랫폼) 으로 초기화
  # - 있을 때: patch_hooks.py로 공통 훅만 최신화 (기기별 설정 보존)
  # - NEVER overwrite via SCP (nah_guard 등 기기 전용 항목 손실 위험)
  local settings_file="$target_dir/settings.json"
  local common_file="$REPO_DIR/configs/settings_common.json"

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

  # 커스텀 스킬은 ~/projects/custom-skills/ 레포에서 관리 (2026-03-29 이전)
  # 배포: bash ~/projects/custom-skills/setup.sh

  # Patch settings.json common hooks (pre-pull scope, push failure detection)
  local settings_file="$target_dir/settings.json"
  if [ -f "$settings_file" ] && command -v python3 &>/dev/null; then
    python3 "$REPO_DIR/scripts/patch_hooks.py" "$settings_file" 2>/dev/null \
      && echo "[OK] settings.json hooks 최신화" \
      || echo "[WARN] settings.json hooks 패치 실패"
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

  # Sync active mode across devices
  local active_mode_src="$REPO_DIR/queue/.active_mode"
  local active_mode_dst="$HOME/.config/agent-orchestration/.active_mode"
  if [ -f "$active_mode_src" ]; then
    mkdir -p "$(dirname "$active_mode_dst")"
    cp "$active_mode_src" "$active_mode_dst"
    echo "[OK] .active_mode → $active_mode_dst (for cross-device sync)"
  fi
  if [ ! -f "$active_mode_src" ] && [ -f "$active_mode_dst" ]; then
    mkdir -p "$(dirname "$active_mode_src")"
    cp "$active_mode_dst" "$active_mode_src"
    echo "[OK] .active_mode ← $active_mode_dst (restored to queue)"
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

  deploy_codex_main

  # Cleanup
  rm -f "$REPO_DIR/adapters/"*.deploy "$REPO_DIR/adapters/"*.bak

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
  # Check deployed files (after SHARED_PRINCIPLES injection)
  check_budget "$BASE_DIR/CLAUDE.md" 160 "~/CLAUDE.md"
  check_budget "$BASE_DIR/.claude/orchestrator_rules.md" 150 "orchestrator_rules.md"
  check_budget "$BASE_DIR/.codex/AGENTS.md" 120 "AGENTS.md (Codex)"
  check_budget "$BASE_DIR/.gemini/GEMINI.md" 150 "GEMINI.md"
  # Check source files
  check_budget "$REPO_DIR/SHARED_PRINCIPLES.md" 50 "SHARED_PRINCIPLES.md (source)"

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
