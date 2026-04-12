#!/usr/bin/env bash
# patch-gemini-companion.sh — Windows 환경에서 플러그인 캐시 호환성 패치
#
# 패치 대상:
# - claude-gemini-plugin: gemini-companion.mjs, gemini-rescue.md
# - openai-codex: codex-companion.mjs
#
# 패치 내용 (Idempotent, 항상 검사):
# 1) gemini-companion: TIMEOUT_MS 테스트값(5s) → 3분 복원
# 2) gemini/codex-companion: process.noDeprecation=true 로 DEP0190 억제
# 3) gemini-rescue.md: Codex fallback의 `--search` 플래그 제거 (Codex task 미지원)
# 4) (레거시) gemini-companion: buildCmdStr → buildGeminiArgs + windowsHide 전환
#
# 사용: bash scripts/device/patch-gemini-companion.sh
# 플러그인 업데이트 후 재실행 필요 (auto-update 시 패치 유실됨)

set -euo pipefail

COMPANION_ROOT="${HOME}/.claude/plugins/cache/claude-gemini-plugin/gemini"

if [ ! -d "$COMPANION_ROOT" ]; then
  echo "[patch] companion root not found: $COMPANION_ROOT"
  exit 1
fi

# 최신 버전 디렉토리 찾기
LATEST_VER=$(ls -1 "$COMPANION_ROOT" | sort -V | tail -1)
TARGET="$COMPANION_ROOT/$LATEST_VER/scripts/gemini-companion.mjs"
AGENT_TARGET="$COMPANION_ROOT/$LATEST_VER/agents/gemini-rescue.md"

if [ ! -f "$TARGET" ]; then
  echo "[patch] gemini-companion.mjs not found: $TARGET"
  exit 1
fi

# TIMEOUT_MS 테스트값 복원 (플러그인 업데이트 시 테스트값 리그레션 방지)
if grep -q 'TIMEOUT_MS = 5 \* 1000' "$TARGET"; then
  sed -i 's|const TIMEOUT_MS = 5 \* 1000;.*|const TIMEOUT_MS = 3 * 60 * 1000;|' "$TARGET"
  echo "[patch] restored TIMEOUT_MS to 3 minutes"
fi

# DEP0190 (shell:true + args array) 경고 억제 — gemini-companion
if ! grep -q 'process.noDeprecation' "$TARGET"; then
  sed -i '0,/^import process from "node:process";$/s||import process from "node:process";\n\nprocess.noDeprecation = true;|' "$TARGET"
  echo "[patch] added process.noDeprecation to gemini-companion"
fi

# gemini-rescue.md agent: Codex fallback의 --search 플래그 제거
if [ -f "$AGENT_TARGET" ] && grep -q 'task --search ARGS' "$AGENT_TARGET"; then
  sed -i 's|task --search ARGS|task ARGS|' "$AGENT_TARGET"
  echo "[patch] stripped --search from gemini-rescue.md Codex fallback"
fi

# codex-companion.mjs: DEP0190 억제
CODEX_ROOT="${HOME}/.claude/plugins/cache/openai-codex/codex"
if [ -d "$CODEX_ROOT" ]; then
  CODEX_LATEST=$(ls -1 "$CODEX_ROOT" | sort -V | tail -1)
  CODEX_TARGET="$CODEX_ROOT/$CODEX_LATEST/scripts/codex-companion.mjs"
  if [ -f "$CODEX_TARGET" ] && ! grep -q 'process.noDeprecation' "$CODEX_TARGET"; then
    sed -i '0,/^import { fileURLToPath } from "node:url";$/s||import { fileURLToPath } from "node:url";\n\nprocess.noDeprecation = true;|' "$CODEX_TARGET"
    echo "[patch] added process.noDeprecation to codex-companion (v$CODEX_LATEST)"
  fi
fi

# 이미 레거시 패치 적용 여부 확인 (buildGeminiArgs 함수가 있으면 이미 패치됨)
if grep -q 'buildGeminiArgs' "$TARGET"; then
  echo "[patch] legacy fixes already applied: $TARGET"
  exit 0
fi

# 백업
cp "$TARGET" "${TARGET}.bak"
echo "[patch] backed up: ${TARGET}.bak"

# sed 패치: buildCmdStr → buildGeminiArgs 방식으로 전환
# 1) buildCmdStr 함수를 buildGeminiArgs로 교체
sed -i 's|^// shell: true 환경에서 안전한 커맨드 문자열 생성|// gemini CLI 실행 인자 배열 구성 (shell:true + array 방식에서는 prompt만 quote)|' "$TARGET"
sed -i 's|^function buildCmdStr(bin, args) {|function buildGeminiArgs(model, prompt) {|' "$TARGET"
sed -i 's|  return \[bin, \.\.\.args\]\.map(shellQuote)\.join(" ");|  return ["--yolo", "-m", model, "-p", shellQuote(prompt)];|' "$TARGET"

# 2) runGemini 내부: cmdStr → geminiArgs
sed -i 's|const cmdStr = buildCmdStr(GEMINI_BIN, \["--yolo", "-m", model, "-p", prompt\]);|const geminiArgs = buildGeminiArgs(model, prompt);|' "$TARGET"

# 3) background wrapper: spawnSync(cmdStr,[],{shell:true}) → spawnSync(BIN, args, {shell:true})
sed -i "s|const r=spawnSync(\${JSON.stringify(cmdStr)},\[\],{shell:true|const r=spawnSync(\${JSON.stringify(GEMINI_BIN)},\${JSON.stringify(geminiArgs)},{shell:true|" "$TARGET"

# 4) foreground: spawnSync(cmdStr, {shell:true}) → spawnSync(GEMINI_BIN, geminiArgs, {shell:true})
sed -i 's|const result = spawnSync(cmdStr, { shell: true|const result = spawnSync(GEMINI_BIN, geminiArgs, { shell: true|' "$TARGET"

# 5) writeJob에 cwd 추가 — 프로젝트명 텔레그램 알림용
sed -i 's|startedAt: new Date().toISOString(), outFile|cwd: process.cwd(), startedAt: new Date().toISOString(), outFile|' "$TARGET"

# 6) windowsHide:true 추가 — CMD 창 숨김
# background wrapper 내부 spawnSync
sed -i 's|{shell:true,encoding:|{shell:true,windowsHide:true,encoding:|' "$TARGET"
# foreground spawnSync
sed -i 's|{ shell: true, encoding: "utf-8"|{ shell: true, windowsHide: true, encoding: "utf-8"|g' "$TARGET"
# background spawn — detached 뒤에 windowsHide 추가
sed -i '/detached: true,/{n;s|stdio: "ignore",|stdio: "ignore",\n      windowsHide: true,|}' "$TARGET"

# 검증
if grep -q 'buildGeminiArgs' "$TARGET" && grep -q 'windowsHide' "$TARGET"; then
  echo "[patch] success: $TARGET (v$LATEST_VER)"
else
  echo "[patch] FAILED — restoring backup"
  cp "${TARGET}.bak" "$TARGET"
  exit 1
fi
