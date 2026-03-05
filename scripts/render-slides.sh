#!/usr/bin/env bash
# render-slides.sh — HTML 슬라이드 → PDF 렌더 + 임시 파일 정리
#
# 사용법:
#   bash render-slides.sh <input.html> [output-name]
#
# 예시:
#   bash render-slides.sh /tmp/slides.html "강아지vs고양이"
#   → ~/Desktop/강아지vs고양이.pdf 생성 후 임시 파일 제거

set -e

# ── 인자 처리 ───────────────────────────────────────────────────────
HTML_FILE="${1:?Usage: render-slides.sh <input.html> [output-name]}"
OUTPUT_NAME="${2:-slides}"

# config에서 설정값 읽기 (없으면 기본값)
CONFIG="$HOME/Desktop/agent-orchestration/slides_config.yaml"
if command -v python3 &>/dev/null && [ -f "$CONFIG" ]; then
  OUTPUT_DIR=$(python3 -c "
import re, sys
txt = open('$CONFIG').read()
m = re.search(r'output_dir:\s*(.+)', txt)
print(m.group(1).strip().replace('~', '$HOME').rstrip()) if m else print('$HOME/Desktop')
" 2>/dev/null || echo "$HOME/Desktop")
  WAIT_MS=$(python3 -c "
import re
txt = open('$CONFIG').read()
m = re.search(r'wait_ms:\s*(\d+)', txt)
print(m.group(1)) if m else print('2000')
" 2>/dev/null || echo "2000")
  PNG_PER_SLIDE=$(python3 -c "
import re
txt = open('$CONFIG').read()
m = re.search(r'png_per_slide:\s*(\w+)', txt)
print(m.group(1)) if m else print('false')
" 2>/dev/null || echo "false")
  CLEANUP_HTML=$(python3 -c "
import re
txt = open('$CONFIG').read()
m = re.search(r'cleanup_html:\s*(\w+)', txt)
print(m.group(1)) if m else print('true')
" 2>/dev/null || echo "true")
else
  OUTPUT_DIR="$HOME/Desktop"
  WAIT_MS=2000
  PNG_PER_SLIDE=false
  CLEANUP_HTML=true
fi

OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
PDF_PATH="$OUTPUT_DIR/$OUTPUT_NAME.pdf"

# ── 임시 JS 렌더 스크립트 생성 ──────────────────────────────────────
TMP_JS=$(mktemp /tmp/render-XXXXXX.js)
ABS_HTML=$(cd "$(dirname "$HTML_FILE")" && pwd)/$(basename "$HTML_FILE")

cat > "$TMP_JS" << JSEOF
const { chromium } = require('playwright');
const path = require('path');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();

  await page.goto('file://${ABS_HTML}');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(${WAIT_MS});

  await page.pdf({
    path: '${PDF_PATH}',
    width: '1280px',
    height: '720px',
    printBackground: true,
    margin: { top: 0, right: 0, bottom: 0, left: 0 },
  });
  console.log('PDF: ${PDF_PATH}');

$(if [ "$PNG_PER_SLIDE" = "true" ]; then
cat << 'PNGEOF'
  const slides = await page.$('.slide');
  // note: $$ not $ for all matches
PNGEOF
fi)
$(if [ "$PNG_PER_SLIDE" = "true" ]; then
cat << PNGEOF2
  const allSlides = await page.$$('.slide');
  for (let i = 0; i < allSlides.length; i++) {
    const p = '${OUTPUT_DIR}/${OUTPUT_NAME}-slide-' + String(i+1).padStart(2,'0') + '.png';
    await allSlides[i].screenshot({ path: p });
    console.log('PNG: ' + p);
  }
PNGEOF2
fi)

  await browser.close();
})();
JSEOF

# ── 렌더 실행 ───────────────────────────────────────────────────────
echo "렌더 중: $HTML_FILE → $PDF_PATH"

# playwright 모듈 위치 찾기 (글로벌 npx 캐시 활용)
cd "$HOME/Desktop" 2>/dev/null || true
node "$TMP_JS"

# ── 정리 ────────────────────────────────────────────────────────────
rm -f "$TMP_JS"

if [ "$CLEANUP_HTML" = "true" ]; then
  rm -f "$HTML_FILE"
  echo "임시 HTML 제거: $HTML_FILE"
fi

echo "완료 → $PDF_PATH"
