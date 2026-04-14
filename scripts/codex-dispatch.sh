#!/usr/bin/env bash
# codex-dispatch.sh — stable wrapper for codex plugin runtime.
#
# 스킬은 companion.mjs 경로를 직접 globbing하지 말고 이 래퍼를 호출한다.
# 플러그인 업그레이드·경로 변경 시 래퍼만 고치면 된다.
#
# Usage:
#   codex-dispatch.sh review [--base <ref>]
#   codex-dispatch.sh adversarial-review [focus text]
#   codex-dispatch.sh task [--model <name>] [--effort <lvl>] <brief>
#   codex-dispatch.sh status [job-id]
#   codex-dispatch.sh result <job-id>
#   codex-dispatch.sh cancel <job-id>
#   codex-dispatch.sh health
#
# 모든 review/adversarial-review/task 호출은 자동으로 --background 부여.
# task의 기본 모델: gpt-5.4. --model 명시 시 해당 값 사용.

set -euo pipefail

COMPANION=$(ls -1 "$HOME"/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1 || true)
if [ -z "${COMPANION:-}" ] || [ ! -f "$COMPANION" ]; then
  echo "ERROR: codex plugin companion not found at ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs" >&2
  echo "       Install the openai-codex Claude Code plugin first." >&2
  exit 2
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "ERROR: codex CLI not found in PATH." >&2
  echo "       Install: npm install -g @openai/codex" >&2
  exit 2
fi

DEFAULT_TASK_MODEL="gpt-5.4"
CMD="${1:-}"
[ -n "$CMD" ] && shift

has_flag() {
  local needle="$1"; shift
  for a in "$@"; do [ "$a" = "$needle" ] && return 0; done
  return 1
}

case "$CMD" in
  review|adversarial-review)
    exec node "$COMPANION" "$CMD" --background "$@"
    ;;
  task|rescue)
    if has_flag "--model" "$@"; then
      exec node "$COMPANION" task --background "$@"
    else
      exec node "$COMPANION" task --background --model "$DEFAULT_TASK_MODEL" "$@"
    fi
    ;;
  status|result|cancel)
    exec node "$COMPANION" "$CMD" "$@"
    ;;
  health)
    echo "companion: $COMPANION"
    echo "codex CLI: $(command -v codex)"
    codex --version 2>&1 || true
    ;;
  ""|-h|--help)
    sed -n '1,20p' "$0"
    ;;
  *)
    echo "ERROR: unknown command '$CMD'. Run with --help for usage." >&2
    exit 1
    ;;
esac
