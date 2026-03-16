#!/usr/bin/env bash
# codex_mcp_setup.sh — Codex CLI MCP 서버 등록
#
# 사전 조건: 아래 환경변수를 먼저 설정해라
#   export PERSONAL_NOTION_TOKEN="secret_..."
#   export COMPANY_NOTION_TOKEN="secret_..."
#   export SLACK_BOT_TOKEN="xoxb-..."
#   export SLACK_TEAM_ID="T..."
#
# 토큰 발급 위치:
#   Notion: https://www.notion.so/my-integrations → 새 통합 생성
#   Slack: https://api.slack.com/apps → Bot Token Scopes
#   Google: gws auth login (브라우저 OAuth, 1회만)
#
# 사용법:
#   bash configs/codex_mcp_setup.sh

set -euo pipefail

echo "--- Codex MCP 서버 등록 ---"

# 기존 MCP 제거 후 재등록 (중복 방지)
for name in notion-personal notion-company obsidian-vault google-workspace slack; do
  codex mcp remove "$name" 2>/dev/null || true
done

# 1. Notion 개인
if [ -n "${PERSONAL_NOTION_TOKEN:-}" ]; then
  codex mcp add notion-personal \
    --env NOTION_API_KEY="$PERSONAL_NOTION_TOKEN" \
    -- npx -y @notionhq/notion-mcp-server
  echo "[OK] notion-personal"
else
  echo "[SKIP] notion-personal — PERSONAL_NOTION_TOKEN 미설정"
fi

# 2. Notion 회사 (읽기 전용 원칙)
if [ -n "${COMPANY_NOTION_TOKEN:-}" ]; then
  codex mcp add notion-company \
    --env NOTION_API_KEY="$COMPANY_NOTION_TOKEN" \
    -- npx -y @notionhq/notion-mcp-server
  echo "[OK] notion-company (쓰기 금지 원칙 적용)"
else
  echo "[SKIP] notion-company — COMPANY_NOTION_TOKEN 미설정"
fi

# 3. Slack
if [ -n "${SLACK_BOT_TOKEN:-}" ] && [ -n "${SLACK_TEAM_ID:-}" ]; then
  codex mcp add slack \
    --env SLACK_BOT_TOKEN="$SLACK_BOT_TOKEN" \
    --env SLACK_TEAM_ID="$SLACK_TEAM_ID" \
    -- npx -y @modelcontextprotocol/server-slack
  echo "[OK] slack"
else
  echo "[SKIP] slack — SLACK_BOT_TOKEN 또는 SLACK_TEAM_ID 미설정"
fi

# 4. Obsidian vault (SSH 경유, 토큰 불필요)
codex mcp add obsidian-vault \
  -- ssh m1 "source ~/.nvm/nvm.sh && npx -y @bitbonsai/mcpvault@latest ~/vault"
echo "[OK] obsidian-vault"

# 5. Google Workspace (gws auth login 별도 필요)
if command -v gws &>/dev/null; then
  codex mcp add google-workspace \
    -- gws mcp -s gmail,calendar,drive
  echo "[OK] google-workspace (인증 필요 시: gws auth login)"
else
  echo "[SKIP] google-workspace — gws 미설치 (npm install -g @googleworkspace/cli)"
fi

echo ""
echo "--- 등록 결과 ---"
codex mcp list
echo ""
echo "Google Workspace 인증: gws auth login"
echo "Notion 토큰 발급: https://www.notion.so/my-integrations"
