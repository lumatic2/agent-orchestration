#!/usr/bin/env bash
# ============================================================
# mcp_setup.sh — Register MCP servers for Claude Code
#
# Usage:
#   GEMINI_API_KEY="your_key" bash config/mcp_setup.sh
#
# Required env vars:
#   GEMINI_API_KEY  — from https://aistudio.google.com/apikey (free tier: 500 img/day)
# ============================================================

set -euo pipefail

echo "--- MCP Server Setup ---"

# Gemini Nanobanana (Gemini 2.5 Flash Image, free 500/day)
if [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "[ERROR] GEMINI_API_KEY is not set. Export it before running this script."
  echo "  export GEMINI_API_KEY=your_key_here"
  exit 1
fi

claude mcp add gemini-nanobanana-mcp -s user \
  -e GEMINI_API_KEY="$GEMINI_API_KEY" \
  -- npx -y gemini-nanobanana-mcp@latest

echo "[OK] gemini-nanobanana-mcp registered (Gemini 2.5 Flash Image, free 500 img/day)"
echo ""
echo "Restart Claude Code to activate MCP servers."
