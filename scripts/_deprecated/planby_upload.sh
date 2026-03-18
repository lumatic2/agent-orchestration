#!/bin/bash
# planby_upload.sh — 파일을 분류하여 적절한 AnythingLLM 워크스페이스에 업로드
# 사용법:
#   bash planby_upload.sh <파일경로>              # 자동 분류
#   bash planby_upload.sh <파일경로> <워크스페이스>  # 수동 지정
#   bash planby_upload.sh --list                 # 워크스페이스별 문서 수 확인
# 워크스페이스: 기준 | 재무세무 | 전략영업 | 회의초안

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/planby_upload.py" "$@"
