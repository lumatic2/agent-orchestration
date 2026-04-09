#!/usr/bin/env bash
# patch-gemini-companion.sh — Windows 환경에서 gemini-companion.mjs 호환성 패치
#
# 패치 내용:
# 1) buildCmdStr + shellQuote → spawnSync(bin, argsArray, {shell:true}) 배열 방식 전환
# 2) windowsHide:true 추가 — CMD 창이 뜨지 않도록
#
# 사용: bash scripts/device/patch-gemini-companion.sh
# 플러그인 업데이트 후 재실행 필요

set -euo pipefail

COMPANION_ROOT="${HOME}/.claude/plugins/cache/claude-gemini-plugin/gemini"

if [ ! -d "$COMPANION_ROOT" ]; then
  echo "[patch] companion root not found: $COMPANION_ROOT"
  exit 1
fi

# 최신 버전 디렉토리 찾기
LATEST_VER=$(ls -1 "$COMPANION_ROOT" | sort -V | tail -1)
TARGET="$COMPANION_ROOT/$LATEST_VER/scripts/gemini-companion.mjs"

if [ ! -f "$TARGET" ]; then
  echo "[patch] gemini-companion.mjs not found: $TARGET"
  exit 1
fi

# 이미 패치 적용 여부 확인 (buildGeminiArgs 함수가 있으면 이미 패치됨)
if grep -q 'buildGeminiArgs' "$TARGET"; then
  echo "[patch] already patched: $TARGET"
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
