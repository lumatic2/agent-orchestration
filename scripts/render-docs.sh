#!/usr/bin/env bash
# render-docs.sh — HTML 문서 → A4 PDF 렌더
#
# 사용법:
#   bash render-docs.sh <input.html> [output-name]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

HTML_FILE="${1:?Usage: render-docs.sh <input.html> [output-name]}"
OUTPUT_NAME="${2:-docs}"

CONFIG="$HOME/Desktop/agent-orchestration/slides_config.yaml"
if command -v python3 &>/dev/null && [ -f "$CONFIG" ]; then
  OUTPUT_DIR=$(python3 -c "
import re
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
  CLEANUP_HTML=$(python3 -c "
import re
txt = open('$CONFIG').read()
m = re.search(r'cleanup_html:\s*(\w+)', txt)
print(m.group(1)) if m else print('true')
" 2>/dev/null || echo "true")
else
  OUTPUT_DIR="$HOME/Desktop"
  WAIT_MS=2000
  CLEANUP_HTML=true
fi

OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
if [[ "$OUTPUT_DIR" =~ ^/([a-zA-Z])/ ]]; then
  OUTPUT_DIR="${BASH_REMATCH[1]^^}:/${OUTPUT_DIR:3}"
fi
PDF_PATH="$OUTPUT_DIR/$OUTPUT_NAME.pdf"

TMP_JS=$(safe_mktemp render-docs .js)
ABS_HTML=$(cd "$(dirname "$HTML_FILE")" && pwd)/$(basename "$HTML_FILE")
if [[ "$ABS_HTML" =~ ^/([a-zA-Z])/ ]]; then
  ABS_HTML="${BASH_REMATCH[1]^^}:/${ABS_HTML:3}"
fi

cat > "$TMP_JS" << JSEOF
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ channel: 'chrome' });
  const page = await browser.newPage();

  await page.goto('file://${ABS_HTML}');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(${WAIT_MS});

  await page.pdf({
    path: '${PDF_PATH}',
    format: 'A4',
    printBackground: true,
    margin: { top: 0, right: 0, bottom: 0, left: 0 },
  });
  console.log('PDF: ${PDF_PATH}');

  await browser.close();
})();
JSEOF

echo "렌더 중: $HTML_FILE → $PDF_PATH"

# NODE_PATH는 env.sh에서 플랫폼별로 설정됨
cd "$HOME/Desktop" 2>/dev/null || true
node "$TMP_JS"

rm -f "$TMP_JS"

if [ "$CLEANUP_HTML" = "true" ]; then
  rm -f "$HTML_FILE"
  echo "임시 HTML 제거: $HTML_FILE"
fi

echo "완료 → $PDF_PATH"
