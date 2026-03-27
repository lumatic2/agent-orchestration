#!/usr/bin/env bash
# research-pipeline.sh — Python 파이프라인 래퍼
# 기존 bash 버전: research-pipeline.sh.bak (2158줄)
# v3 cutover: 2026-03-27

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

exec python3 -m pipeline "$@"
