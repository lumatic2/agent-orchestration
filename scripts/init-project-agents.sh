#!/usr/bin/env bash
# ============================================================
# init-project-agents.sh — 프로젝트 루트에 Codex용 AGENTS.md stub 생성
# ------------------------------------------------------------
# Codex는 세션 시작 시 현재 작업 디렉토리의 AGENTS.md를 자동으로 읽지만
# CLAUDE.md는 읽지 않는다. 이 스크립트는 프로젝트 루트에 짧은 AGENTS.md
# stub을 생성해, Codex가 CLAUDE.md를 명시적으로 읽도록 유도한다.
#
# 사용법:
#   cd ~/projects/<project-name>
#   bash ~/projects/agent-orchestration/scripts/init-project-agents.sh
#
# 옵션:
#   --force    기존 AGENTS.md 덮어쓰기 (기본: 있으면 중단)
#   --dir PATH 대상 디렉토리 지정 (기본: 현재 디렉토리)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

FORCE=0
TARGET_DIR="$(pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --dir)   TARGET_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,17p' "$0"
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [ ! -d "$TARGET_DIR" ]; then
  echo "[ERROR] Target directory not found: $TARGET_DIR" >&2
  exit 1
fi

AGENTS_FILE="$TARGET_DIR/AGENTS.md"
CLAUDE_FILE="$TARGET_DIR/CLAUDE.md"
PROJECT_NAME="$(basename "$TARGET_DIR")"

if [ -f "$AGENTS_FILE" ] && [ "$FORCE" -ne 1 ]; then
  echo "[SKIP] $AGENTS_FILE already exists. Use --force to overwrite."
  exit 0
fi

# Detect whether CLAUDE.md exists to decide the stub body
if [ -f "$CLAUDE_FILE" ]; then
  cat > "$AGENTS_FILE" <<EOF
# AGENTS.md — $PROJECT_NAME

> Codex 프로젝트 스코프 규칙. 생성: scripts/init-project-agents.sh

## 공통 원칙

공통 원칙(Identity, Behavioral Rules, Infrastructure Protection, Worker Agent 규칙)은
홈 스코프 \`~/.codex/AGENTS.md\` 에서 이미 로드됐다. 여기서는 중복하지 않는다.

## 프로젝트 규칙

이 프로젝트의 상세 규칙·구조·관례는 같은 디렉토리의 \`CLAUDE.md\`에 있다.
**세션 시작 시 반드시 \`./CLAUDE.md\`를 읽고 시작할 것.** CLAUDE.md에는:

- 프로젝트 기술 스택과 구조
- 개발 명령어 및 관례
- 보호 파일 / 금지 사항
- 기타 이 프로젝트 고유의 작업 방식

이 담겨 있다. \`CLAUDE.md\`의 내용 중 "Claude 전용"(Skill 도구 호출 규칙, 모델
라우팅 등) 문구는 무시해도 되지만, 프로젝트 구조·규칙은 그대로 따른다.
EOF
else
  cat > "$AGENTS_FILE" <<EOF
# AGENTS.md — $PROJECT_NAME

> Codex 프로젝트 스코프 규칙. 생성: scripts/init-project-agents.sh

## 공통 원칙

공통 원칙은 홈 스코프 \`~/.codex/AGENTS.md\` 에서 이미 로드됐다.

## 프로젝트 규칙

(프로젝트 고유 규칙을 여기에 작성. CLAUDE.md가 없는 프로젝트이므로 스택·구조·
관례를 직접 기술하거나, 나중에 CLAUDE.md를 만들면 이 파일을 업데이트한다.)

- **기술 스택**: (예: Python 3.11, FastAPI, Postgres)
- **구조**: (주요 디렉토리 한 줄 설명)
- **개발 명령어**: (예: \`uv run pytest\`, \`ruff check\`)
- **주의**: (보호 파일, 금지 사항)
EOF
fi

echo "[OK] Created $AGENTS_FILE"
if [ -f "$CLAUDE_FILE" ]; then
  echo "[INFO] CLAUDE.md detected — stub references it."
else
  echo "[INFO] No CLAUDE.md found — generated generic template. Fill in project details."
fi
