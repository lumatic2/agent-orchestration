#!/usr/bin/env bash
# slack-send.sh — Slack Incoming Webhook으로 메시지 전송

set -uo pipefail

DRY_RUN=false
MESSAGE_TEXT=""

usage() {
  echo "Usage: bash slack-send.sh [--dry-run] --message \"text\"" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --message) shift; MESSAGE_TEXT="$1"; shift ;;
    --message=*) MESSAGE_TEXT="${1#--message=}"; shift ;;
    -h|--help) usage ;;
    *) echo "[ERROR] Unknown option: $1" >&2; usage ;;
  esac
done

[[ -z "$MESSAGE_TEXT" ]] && { echo "[ERROR] --message 필요" >&2; exit 1; }

# Load secrets: GCP Secret Manager → .env fallback
_S="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/secrets_load.sh"
# shellcheck disable=SC1090
[ -f "$_S" ] && source "$_S" 2>/dev/null; unset _S

if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
  echo "[ERROR] SLACK_WEBHOOK_URL 미설정 (.env 또는 환경변수 확인)" >&2
  exit 1
fi

# Slack은 줄바꿈을 \n으로 처리
ESCAPED=$(printf '%s' "$MESSAGE_TEXT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

if [[ "$DRY_RUN" == "true" ]]; then
  echo "would send slack message: $MESSAGE_TEXT"
  exit 0
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$SLACK_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{\"text\": $ESCAPED}")

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "[SENT] Slack message delivered"
else
  echo "[ERROR] Slack 전송 실패 (HTTP $HTTP_CODE)" >&2
  exit 1
fi
