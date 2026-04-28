#!/usr/bin/env bash
# ============================================================
# sync-codex-skills.sh — Codex 와 공유할 스킬 동기화
#
# What it does:
#   1. ~/projects/custom-skills/*/SKILL.md 스캔
#   2. frontmatter 에 `codex: true` 인 스킬을 ~/.codex/skills/ 로 복사
#   3. 인자로 받은 AGENTS.md 끝에 "Custom Commands" 인덱스 섹션 append
#
# 호출은 sync.sh 의 deploy_codex 에서. 단독 실행도 가능 (테스트용).
#
# Usage:
#   bash sync-codex-skills.sh [TARGET_AGENTS_PATH]
#   기본 TARGET = ~/.codex/AGENTS.md
# ============================================================

set -euo pipefail

TARGET_AGENTS="${1:-$HOME/.codex/AGENTS.md}"
SKILLS_SRC_DIR="$HOME/projects/custom-skills"
CODEX_SKILLS_DIR="$HOME/.codex/skills"

if [ ! -d "$SKILLS_SRC_DIR" ]; then
  echo "[SKIP] $SKILLS_SRC_DIR not found — skipping shared skill sync"
  exit 0
fi

mkdir -p "$CODEX_SKILLS_DIR"

# 이전 동기화 잔재 제거 (codex: true 플래그 해제 시 자동 반영)
rm -f "$CODEX_SKILLS_DIR"/*.md

shared_skills=()

for skill_md in "$SKILLS_SRC_DIR"/*/SKILL.md; do
  [ -f "$skill_md" ] || continue

  # frontmatter (--- 사이) 안에 `codex: true` 가 있는지 확인
  if awk '
    BEGIN { in_fm = 0; found = 0 }
    /^---[[:space:]]*$/ {
      if (in_fm == 0) { in_fm = 1; next }
      else { exit !found }
    }
    in_fm && /^codex:[[:space:]]*true[[:space:]]*$/ { found = 1 }
  ' "$skill_md"; then
    skill_name="$(basename "$(dirname "$skill_md")")"
    cp "$skill_md" "$CODEX_SKILLS_DIR/$skill_name.md"
    shared_skills+=("$skill_name")
    echo "[OK] shared skill → $CODEX_SKILLS_DIR/$skill_name.md"
  fi
done

if [ ${#shared_skills[@]} -eq 0 ]; then
  echo "[INFO] No skills marked 'codex: true' — Custom Commands section not appended"
  exit 0
fi

# AGENTS.md 끝에 Custom Commands 섹션 append
{
  echo ""
  echo "---"
  echo ""
  echo "## Custom Commands"
  echo ""
  echo "사용자가 아래 슬래시 명령 중 하나를 입력하면, 해당 파일을 읽고 그 안의 절차를 그대로 따른다:"
  echo ""
  for name in "${shared_skills[@]}"; do
    echo "- \`/$name\` → \`~/.codex/skills/$name.md\`"
  done
  echo ""
} >> "$TARGET_AGENTS"

echo "[OK] Appended Custom Commands index (${#shared_skills[@]} skill) → $TARGET_AGENTS"
