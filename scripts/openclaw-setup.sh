#!/usr/bin/env bash
# openclaw-setup.sh — OpenClaw 에이전트 설정 배포
# Usage: bash openclaw-setup.sh
# 레포의 openclaw/ 설정을 ~/.openclaw/에 복사

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_DIR/openclaw"
DST="$HOME/.openclaw"

echo "[1/3] 디렉토리 생성..."
mkdir -p "$DST/agents/main" "$DST/logs"

echo "[2/3] 설정 파일 복사..."
cp "$SRC/agents/main/SOUL.md"  "$DST/agents/main/SOUL.md"
cp "$SRC/agents/main/TOOLS.md" "$DST/agents/main/TOOLS.md"
cp "$SRC/bridge.sh"            "$DST/bridge.sh"
chmod +x "$DST/bridge.sh"

echo "[3/3] 완료"
echo ""
echo "~/.openclaw/agents/main/SOUL.md  ✓"
echo "~/.openclaw/agents/main/TOOLS.md ✓"
echo "~/.openclaw/bridge.sh            ✓"
echo ""
echo "남은 작업: ~/.zshenv에 환경변수 설정 확인"
echo "  TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID"
echo "  PERSONAL_NOTION_TOKEN, NOTION_SLIDES_PAGE_ID"
