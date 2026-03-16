#!/usr/bin/env bash
# new-script.sh — scripts/ 디렉토리에 새 스크립트 뼈대 생성
# Usage: bash new-script.sh <스크립트명> ["설명"]
#
# 예시:
#   bash new-script.sh report.sh "일간 리포트 생성"

set -euo pipefail

NAME="${1:?Usage: bash new-script.sh <스크립트명> [\"설명\"]}"
DESC="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$SCRIPT_DIR/$NAME"

if [ -f "$OUT" ]; then
  echo "[ERROR] 이미 존재합니다: $OUT" >&2
  exit 1
fi

# .sh 확장자 없으면 자동 추가
[[ "$NAME" == *.sh ]] || { OUT="${OUT}.sh"; NAME="${NAME}.sh"; }

cat > "$OUT" << TEMPLATE
#!/usr/bin/env bash
# ${NAME} — ${DESC}
# Usage: bash ${NAME} <arg>

set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
source "\$SCRIPT_DIR/env.sh"

# ── 인자 처리 ────────────────────────────────────────────────
ARG="\${1:?Usage: bash ${NAME} <arg>}"

# ── 메인 로직 ────────────────────────────────────────────────

TEMPLATE

chmod +x "$OUT"
echo "생성됨: $OUT"
