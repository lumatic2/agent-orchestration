#!/usr/bin/env bash
# env.sh — 플랫폼 감지 및 공통 환경 변수
#
# 사용법:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/env.sh"

# ── 플랫폼 감지 ─────────────────────────────────────────────
if [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* || -d "${HOME}/AppData" ]]; then
  PLATFORM="windows"
else
  PLATFORM="mac"
fi
export PLATFORM

# ── 임시 디렉토리 ────────────────────────────────────────────
# Windows: /tmp은 Node.js(Playwright)가 접근 불가 → AppData/Local/Temp 사용
if [[ "$PLATFORM" == "windows" ]]; then
  SYS_TMP="${HOME}/AppData/Local/Temp"
  mkdir -p "$SYS_TMP"
else
  SYS_TMP="/tmp"
fi
export SYS_TMP

# ── Node.js 모듈 경로 ────────────────────────────────────────
# Windows: npm global 모듈이 AppData 아래에 위치
if [[ "$PLATFORM" == "windows" ]]; then
  _WIN_NPM="/c/Users/1/AppData/Roaming/npm/node_modules"
  _FALLBACK="$HOME/Desktop/node_modules"
  _PLAYWRIGHT_PATHS="$(node -e 'console.log(require.resolve.paths("playwright").join(":"))' 2>/dev/null || true)"
  export NODE_PATH="${_WIN_NPM}:${_FALLBACK}:${_PLAYWRIGHT_PATHS}"
else
  export NODE_PATH="$(node -e 'console.log(require.resolve.paths("playwright").join(":"))' 2>/dev/null || true)"
fi

# ── mktemp 헬퍼 ──────────────────────────────────────────────
# macOS는 파일명에 비 ASCII 문자가 포함되면 XXXXXX를 치환하지 않는 버그가 있음
# 반드시 ASCII-only prefix를 사용할 것
safe_mktemp() {
  local prefix="${1:-tmp}"   # ASCII only
  local suffix="${2:-.txt}"
  mktemp "${SYS_TMP}/${prefix}-XXXXXX${suffix}"
}
export -f safe_mktemp
