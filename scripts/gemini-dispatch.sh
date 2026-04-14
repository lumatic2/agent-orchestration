#!/usr/bin/env bash
# gemini-dispatch.sh — stable wrapper for gemini plugin runtime.
#
# 스킬은 companion.mjs 경로를 직접 globbing하지 말고 이 래퍼를 호출한다.
# 플러그인 업그레이드·경로 변경 시 래퍼만 고치면 된다.
#
# Usage:
#   gemini-dispatch.sh task [--model <name>] <brief>
#   gemini-dispatch.sh review [--base <ref>]
#   gemini-dispatch.sh status [job-id]
#   gemini-dispatch.sh result <job-id>
#   gemini-dispatch.sh cancel <job-id>
#   gemini-dispatch.sh health
#
# 모든 task/review 호출은 자동으로 --background 부여.
# task의 기본 모델: gemini-2.5-flash (빠름·저비용, 대부분의 교차검증에 충분).
# 대용량/심층 분석 필요 시 `--model gemini-2.5-pro` 명시.
# pro/flash alias는 preview를 가리키므로 사용 금지 — 풀 이름 지정 권장.

set -euo pipefail

COMPANION=$(ls -1 "$HOME"/.claude/plugins/cache/claude-gemini-plugin/gemini/*/scripts/gemini-companion.mjs 2>/dev/null | sort -V | tail -1 || true)
if [ -z "${COMPANION:-}" ] || [ ! -f "$COMPANION" ]; then
  echo "ERROR: gemini plugin companion not found at ~/.claude/plugins/cache/claude-gemini-plugin/gemini/*/scripts/gemini-companion.mjs" >&2
  echo "       Install the claude-gemini-plugin Claude Code plugin first." >&2
  exit 2
fi

if ! command -v gemini >/dev/null 2>&1; then
  echo "ERROR: gemini CLI not found in PATH." >&2
  echo "       Install: npm install -g @google/gemini-cli" >&2
  exit 2
fi

DEFAULT_TASK_MODEL="gemini-2.5-flash"
CMD="${1:-}"
[ -n "$CMD" ] && shift

has_flag() {
  local needle="$1"; shift
  for a in "$@"; do [ "$a" = "$needle" ] && return 0; done
  return 1
}

case "$CMD" in
  task|rescue)
    if has_flag "--model" "$@"; then
      exec node "$COMPANION" task --background "$@"
    else
      exec node "$COMPANION" task --background --model "$DEFAULT_TASK_MODEL" "$@"
    fi
    ;;
  review)
    exec node "$COMPANION" review --background "$@"
    ;;
  status|result|cancel)
    exec node "$COMPANION" "$CMD" "$@"
    ;;
  health)
    echo "companion: $COMPANION"
    echo "gemini CLI: $(command -v gemini)"
    gemini --version 2>&1 || true
    ;;
  ""|-h|--help)
    sed -n '1,20p' "$0"
    ;;
  *)
    echo "ERROR: unknown command '$CMD'. Run with --help for usage." >&2
    exit 1
    ;;
esac
