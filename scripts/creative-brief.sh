#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
source "$SCRIPT_DIR/secrets_load.sh" 2>/dev/null || true

exec python3 "$SCRIPT_DIR/creative-brief.py" "$@"