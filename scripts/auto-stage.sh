#!/usr/bin/env bash
# auto-stage.sh — PostToolUse 훅: 파일 수정 시 자동 git add (스테이징만)

set -uo pipefail

INPUT="${1:-}"
[[ -z "$INPUT" ]] && exit 0

# TOOL_INPUT JSON에서 file_path 추출
FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('file_path', ''))
except:
    print('')
" 2>/dev/null)

[[ -z "$FILE_PATH" ]] && exit 0

# 절대 경로로 변환 (eval 사용하지 않음 — 인젝션 방지)
FILE_PATH="${FILE_PATH/#\~/$HOME}"
[[ -f "$FILE_PATH" ]] || exit 0

# 파일이 git 레포 안에 있는지 확인
REPO_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null)
[[ -z "$REPO_ROOT" ]] && exit 0

# .env, secrets 등 민감 파일 제외
case "$FILE_PATH" in
  */.env|*/.env.*|*/secrets*|*/credentials*|*/id_rsa*|*/private_key*)
    exit 0 ;;
esac

# git add
git -C "$REPO_ROOT" add "$FILE_PATH" 2>/dev/null && \
  echo "[auto-stage] staged: ${FILE_PATH#$REPO_ROOT/}" || true
