#!/usr/bin/env bash
# gemini-dispatch.sh — stable wrapper for gemini plugin runtime.
#
# 스킬은 companion.mjs 경로를 직접 globbing하지 말고 이 래퍼를 호출한다.
# 플러그인 업그레이드·경로 변경 시 래퍼만 고치면 된다.
#
# Usage:
#   gemini-dispatch.sh task [--model <name>] [--no-context] <brief>
#   gemini-dispatch.sh explore <question>     # read-only 조사
#   gemini-dispatch.sh review [--base <ref>]
#   gemini-dispatch.sh status [job-id]
#   gemini-dispatch.sh result <job-id>
#   gemini-dispatch.sh cancel <job-id>
#   gemini-dispatch.sh health
#
# 모든 task/explore/review 호출은 자동으로 --background 부여.
# task의 기본 모델: gemini-2.5-flash (빠름·저비용).
# 대용량/심층 분석 필요 시 `--model gemini-2.5-pro` 명시.
# pro/flash alias는 preview를 가리키므로 사용 금지 — 풀 이름 지정.
#
# Context injection:
#   task/explore 호출 시 git root의 CLAUDE.md를 brief 앞에 자동 주입.
#   --no-context 플래그로 비활성화.
#
# NOTE: Gemini companion은 thread resume 미지원. 연속 작업은 새 task로 시작.

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

# 프로젝트 CLAUDE.md를 읽어 컨텍스트 헤더 반환.
# git repo root 기준 탐색 → 하위 디렉토리·worktree에서 호출해도 동작.
build_project_context() {
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  local claude_md=""
  if [ -n "$git_root" ] && [ -f "$git_root/CLAUDE.md" ]; then
    claude_md="$git_root/CLAUDE.md"
  elif [ -f "$(pwd)/CLAUDE.md" ]; then
    claude_md="$(pwd)/CLAUDE.md"
  fi

  # Gemini Flash는 긴 prepended context가 짧은 brief를 압도하는 경향.
  # → brief를 앞에 두고 CLAUDE.md는 뒤에 reference로 첨부 (Option D).
  if [ -n "$claude_md" ]; then
    printf "%s" "$claude_md"
  else
    printf ""
  fi
}

inject_context() {
  local brief="$1"
  local claude_md
  claude_md="$(build_project_context)"
  if [ -n "$claude_md" ]; then
    printf "%s\n\n---\n[참고: 프로젝트 컨벤션 — %s. 위 작업과 직접 관련 없으면 무시하라.]\n%s" \
      "$brief" "$claude_md" "$(cat "$claude_md")"
  else
    printf "%s" "$brief"
  fi
}

case "$CMD" in
  explore)
    # Read-only 조사 모드. side-effect 없음 → confirm 불필요.
    BRIEF="${*}"
    if [ -z "$BRIEF" ]; then
      echo "ERROR: explore requires a question." >&2
      exit 1
    fi
    READ_ONLY_HEADER="[READ-ONLY EXPLORATION — 파일을 생성·수정·삭제하지 마시오. 조사 결과만 보고할 것.]

"
    ENRICHED="$(inject_context "${READ_ONLY_HEADER}${BRIEF}")"
    exec node "$COMPANION" task --background --model "$DEFAULT_TASK_MODEL" "$ENRICHED"
    ;;

  task|rescue)
    # --no-context 플래그 분리
    NO_CONTEXT=false
    REMAINING=()
    for a in "$@"; do
      if [ "$a" = "--no-context" ]; then
        NO_CONTEXT=true
      else
        REMAINING+=("$a")
      fi
    done

    # 컨텍스트 주입: 마지막 인자(brief)에 prepend
    if [ "$NO_CONTEXT" = false ] && [ "${#REMAINING[@]}" -gt 0 ]; then
      LAST_IDX=$(( ${#REMAINING[@]} - 1 ))
      BRIEF="${REMAINING[$LAST_IDX]}"
      if [[ "$BRIEF" != --* ]]; then
        REMAINING[$LAST_IDX]="$(inject_context "$BRIEF")"
      fi
    fi

    if has_flag "--model" "${REMAINING[@]+"${REMAINING[@]}"}"; then
      exec node "$COMPANION" task --background "${REMAINING[@]+"${REMAINING[@]}"}"
    else
      exec node "$COMPANION" task --background --model "$DEFAULT_TASK_MODEL" "${REMAINING[@]+"${REMAINING[@]}"}"
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
    echo ""
    GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    CLAUDE_MD=""
    if [ -n "$GIT_ROOT" ] && [ -f "$GIT_ROOT/CLAUDE.md" ]; then
      CLAUDE_MD="$GIT_ROOT/CLAUDE.md"
    elif [ -f "$(pwd)/CLAUDE.md" ]; then
      CLAUDE_MD="$(pwd)/CLAUDE.md"
    fi
    if [ -n "$CLAUDE_MD" ]; then
      echo "context injection: ON ($(wc -l < "$CLAUDE_MD") lines from $CLAUDE_MD)"
    else
      echo "context injection: OFF (no CLAUDE.md found in git root or cwd)"
    fi
    echo "resume support: NOT available (gemini companion limitation)"
    ;;

  ""|-h|--help)
    sed -n '1,25p' "$0"
    ;;

  *)
    echo "ERROR: unknown command '$CMD'. Run with --help for usage." >&2
    exit 1
    ;;
esac
