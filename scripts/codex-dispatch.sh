#!/usr/bin/env bash
# codex-dispatch.sh — stable wrapper for codex plugin runtime.
#
# 스킬은 companion.mjs 경로를 직접 globbing하지 말고 이 래퍼를 호출한다.
# 플러그인 업그레이드·경로 변경 시 래퍼만 고치면 된다.
#
# Usage:
#   codex-dispatch.sh review [--base <ref>]
#   codex-dispatch.sh adversarial-review [focus text]
#   codex-dispatch.sh explore <question>          # read-only 조사
#   codex-dispatch.sh task [--model <name>] [--effort <lvl>] [--no-context] [--resume] <brief>
#   codex-dispatch.sh resume [<brief>]            # 마지막 task thread 이어서 실행
#   codex-dispatch.sh wait <job-id>          # 잡 완료까지 블록 후 결과 출력 (notification용)
#   codex-dispatch.sh status [job-id]
#   codex-dispatch.sh result <job-id>
#   codex-dispatch.sh cancel <job-id>
#   codex-dispatch.sh last-thread                 # 마지막 저장된 task thread 정보
#   codex-dispatch.sh health
#
# 모든 review/adversarial-review/task/explore 호출은 자동으로 --background 부여.
# task의 기본 모델: gpt-5.4. --model 명시 시 해당 값 사용.
#
# Context injection:
#   task/explore 호출 시 ./CLAUDE.md를 brief 앞에 자동 주입.
#   --no-context 플래그로 비활성화.

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

# 프로젝트 CLAUDE.md를 읽어 컨텍스트 헤더 반환.
# git repo root 기준으로 탐색 → 하위 디렉토리·worktree에서 호출해도 동작.
# 없으면 빈 문자열.
build_project_context() {
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  local claude_md=""
  if [ -n "$git_root" ] && [ -f "$git_root/CLAUDE.md" ]; then
    claude_md="$git_root/CLAUDE.md"
  elif [ -f "$(pwd)/CLAUDE.md" ]; then
    claude_md="$(pwd)/CLAUDE.md"
  fi

  if [ -n "$claude_md" ]; then
    printf "=== 프로젝트 컨벤션 (%s) ===\n%s\n\n=== 작업 지시 ===\n" "$claude_md" "$(cat "$claude_md")"
  else
    printf ""
  fi
}

# brief 앞에 프로젝트 컨텍스트를 주입한 문자열 반환.
inject_context() {
  local brief="$1"
  local ctx
  ctx="$(build_project_context)"
  if [ -n "$ctx" ]; then
    printf "%s%s" "$ctx" "$brief"
  else
    printf "%s" "$brief"
  fi
}

case "$CMD" in
  review|adversarial-review)
    exec node "$COMPANION" "$CMD" --background "$@"
    ;;

  explore)
    # Read-only 조사 모드. side-effect 없음 → confirm 불필요.
    # "$@" 전체가 질문/지시문. 컨텍스트 자동 주입.
    BRIEF="${*}"
    if [ -z "$BRIEF" ]; then
      echo "ERROR: explore requires a question. e.g.: codex-dispatch.sh explore '이 버그 원인 찾아줘'" >&2
      exit 1
    fi
    READ_ONLY_HEADER="[READ-ONLY EXPLORATION — 파일을 생성·수정·삭제하지 마시오. 조사 결과만 보고할 것.]

"
    ENRICHED="$(inject_context "${READ_ONLY_HEADER}${BRIEF}")"
    exec node "$COMPANION" task --background --model "$DEFAULT_TASK_MODEL" "$ENRICHED"
    ;;

  resume)
    # 마지막 task thread를 이어서 실행. 선택적으로 추가 지시문 전달 가능.
    # 인자 없으면 companion 기본 continue prompt 사용.
    RESUME_BRIEF="${*}"
    if [ -n "$RESUME_BRIEF" ]; then
      RESUME_BRIEF="$(inject_context "$RESUME_BRIEF")"
      exec node "$COMPANION" task --background --resume-last --model "$DEFAULT_TASK_MODEL" "$RESUME_BRIEF"
    else
      exec node "$COMPANION" task --background --resume-last --model "$DEFAULT_TASK_MODEL"
    fi
    ;;

  last-thread)
    # 마지막 저장된 task thread ID·이름 출력 (resume 전 확인용)
    tail -1 "$HOME/.codex/session_index.jsonl" 2>/dev/null \
      | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log('id:  '+d.id+'\nname:'+d.thread_name+'\nupdated:'+d.updated_at)" \
      || echo "no task threads found"
    ;;

  task|rescue)
    # 플래그 파싱: --no-context, --resume 분리
    NO_CONTEXT=false
    RESUME=false
    REMAINING=()
    for a in "$@"; do
      case "$a" in
        --no-context) NO_CONTEXT=true ;;
        --resume)     RESUME=true ;;
        *)            REMAINING+=("$a") ;;
      esac
    done

    # resume 모드: 마지막 thread 이어서, brief는 선택
    if [ "$RESUME" = true ]; then
      if [ "${#REMAINING[@]}" -gt 0 ]; then
        BRIEF="${REMAINING[${#REMAINING[@]}-1]}"
        if [[ "$BRIEF" != --* ]] && [ "$NO_CONTEXT" = false ]; then
          REMAINING[${#REMAINING[@]}-1]="$(inject_context "$BRIEF")"
        fi
        exec node "$COMPANION" task --background --resume-last "${REMAINING[@]+"${REMAINING[@]}"}"
      else
        exec node "$COMPANION" task --background --resume-last --model "$DEFAULT_TASK_MODEL"
      fi
    fi

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

  wait)
    # Codex 잡이 실제로 완료될 때까지 블록. run_in_background:true로 호출하면
    # 잡 완료 시 <task-notification>이 발생 — 올바른 완료 감지 방법.
    # Usage: codex-dispatch.sh wait <job-id>
    JOB_ID="${1:-}"
    if [ -z "$JOB_ID" ]; then
      echo "ERROR: wait requires a job-id" >&2
      exit 1
    fi
    # Plugin state dir (current layout — codex plugin >= 2025-Q4)
    LOG_BASE="$HOME/.claude/plugins/data/codex-openai-codex/state"
    LOG=$(ls -1 "$LOG_BASE"/*/jobs/"$JOB_ID".log 2>/dev/null | head -1 || true)
    # Legacy temp-dir layout (older codex plugin builds)
    LEGACY_BASE="$HOME/AppData/Local/Temp/codex-companion"
    if [ -z "$LOG" ]; then
      LOG=$(ls -1 "$LEGACY_BASE"/*/jobs/"$JOB_ID".log 2>/dev/null | head -1 || true)
    fi
    if [ -z "$LOG" ]; then
      echo "ERROR: log not found for '$JOB_ID'" >&2
      echo "       Searched: $LOG_BASE/*/jobs/$JOB_ID.log" >&2
      echo "                 $LEGACY_BASE/*/jobs/$JOB_ID.log" >&2
      exit 1
    fi
    # 이미 완료된 경우 즉시 통과, 아니면 tail -f | grep -m1으로 sleep 없이 대기
    if ! grep -q "Final output\|Turn completion inferred" "$LOG" 2>/dev/null; then
      tail -f "$LOG" | grep -m 1 "Final output\|Turn completion inferred" >/dev/null 2>&1 || true
    fi
    echo "=== Codex job $JOB_ID completed ==="
    node "$COMPANION" result "$JOB_ID" 2>/dev/null \
      || grep -A 500 "\] Final output" "$LOG" | head -150
    ;;

  status|result|cancel|thread)
    exec node "$COMPANION" "$CMD" "$@"
    ;;

  health)
    echo "companion: $COMPANION"
    echo "codex CLI: $(command -v codex)"
    codex --version 2>&1 || true
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
    ;;

  ""|-h|--help)
    sed -n '1,25p' "$0"
    ;;

  *)
    echo "ERROR: unknown command '$CMD'. Run with --help for usage." >&2
    exit 1
    ;;
esac
