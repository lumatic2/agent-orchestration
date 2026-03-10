#!/usr/bin/env bash

set -uo pipefail

DRY_RUN=false
MODE="file"
MESSAGE_TEXT=""

usage() {
  echo "Usage:" >&2
  echo "  bash telegram-send.sh [--dry-run] <file_or_message> [caption]" >&2
  echo "  bash telegram-send.sh [--dry-run] --message \"text\"" >&2
  exit 1
}

if [ "$#" -eq 0 ]; then
  usage
fi

args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --message)
      MODE="message"
      shift
      if [ "$#" -eq 0 ]; then
        echo "[ERROR] --message 뒤에 텍스트를 입력하세요." >&2
        exit 1
      fi
      MESSAGE_TEXT="$1"
      shift
      ;;
    --message=*)
      MODE="message"
      MESSAGE_TEXT="${1#--message=}"
      shift
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        args+=("$1")
        shift
      done
      ;;
    -*)
      echo "[ERROR] 알 수 없는 옵션: $1" >&2
      usage
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [ "$DRY_RUN" = false ]; then
  if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    echo "[ERROR] TELEGRAM_BOT_TOKEN 또는 TELEGRAM_CHAT_ID 미설정" >&2
    echo "  ~/.zshenv에 추가:" >&2
    echo "  export TELEGRAM_BOT_TOKEN=7xxx:AAF-xxx" >&2
    echo "  export TELEGRAM_CHAT_ID=-100xxxxxx" >&2
    exit 1
  fi
fi

send_message() {
  local text="$1"
  local result

  if [ "$DRY_RUN" = true ]; then
    echo "would send message: $text"
    return 0
  fi

  result=$(curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${text}" \
    -d "parse_mode=HTML" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK' if d.get('ok') else f'ERR: {d}')")

  if [ "$result" = "OK" ]; then
    return 0
  fi

  echo "$result"
  return 1
}

send_file() {
  local file="$1"
  local caption="${2:-}"
  local ext
  local file_size
  local method
  local field
  local result

  if [ "$DRY_RUN" = true ]; then
    echo "would send: $file"
    return 0
  fi

  if [ ! -f "$file" ]; then
    echo "ERR: file not found: $file"
    return 1
  fi

  ext="${file##*.}"
  ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"

  file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
  if [ -z "${file_size:-}" ]; then
    echo "ERR: 파일 크기 확인 실패: $file"
    return 1
  fi

  if [ "$file_size" -gt 52428800 ]; then
    echo "[WARN] 파일 크기 초과 (${file_size} bytes > 50MB). 메시지로 경로 전송." >&2
    if send_message "파일이 너무 큽니다 ($(( file_size / 1024 / 1024 ))MB). 경로: $file"; then
      echo "OK"
      return 0
    fi
    echo "ERR: 파일 크기 초과 후 대체 메시지 전송 실패"
    return 1
  fi

  case "$ext" in
    jpg|jpeg|png|gif|webp)
      method="sendPhoto"
      field="photo"
      ;;
    *)
      method="sendDocument"
      field="document"
      ;;
  esac

  result=$(curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/${method}" \
    -F "chat_id=${TELEGRAM_CHAT_ID}" \
    -F "${field}=@${file}" \
    -F "caption=${caption}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK' if d.get('ok') else f'ERR: {d.get(\"description\",d)}')")

  echo "$result"
  [ "$result" = "OK" ]
}

if [ "$MODE" = "message" ]; then
  if [ -z "$MESSAGE_TEXT" ] && [ "${#args[@]}" -gt 0 ]; then
    MESSAGE_TEXT="${args[*]}"
  fi

  if [ -z "$MESSAGE_TEXT" ]; then
    echo "[ERROR] 전송할 메시지가 비어 있습니다." >&2
    exit 1
  fi

  if send_message "$MESSAGE_TEXT"; then
    echo "[SENT] message → chat ${TELEGRAM_CHAT_ID:-DRY_RUN}"
    exit 0
  fi

  echo "[FAIL] message send failed"
  exit 1
fi

if [ "${#args[@]}" -lt 1 ]; then
  usage
fi

caption=""
files=("${args[@]}")
if [ "${#args[@]}" -ge 2 ]; then
  last_index=$((${#args[@]} - 1))
  last_arg="${args[$last_index]}"
  if [ ! -f "$last_arg" ]; then
    caption="$last_arg"
    unset 'files[$last_index]'
    files=("${files[@]}")
  fi
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "[ERROR] 전송할 파일이 없습니다." >&2
  exit 1
fi

fail_count=0
for f in "${files[@]}"; do
  result="$(send_file "$f" "$caption")"
  if [ "$result" = "would send: $f" ]; then
    echo "$result"
    echo "[SENT] $(basename "$f") → chat ${TELEGRAM_CHAT_ID:-DRY_RUN}"
  elif [ "$result" = "OK" ]; then
    echo "[SENT] $(basename "$f") → chat ${TELEGRAM_CHAT_ID:-DRY_RUN}"
  else
    echo "[FAIL] $result"
    fail_count=$((fail_count + 1))
  fi
done

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi

exit 0
