#!/usr/bin/env bash
# secrets_load.sh — GCP Secret Manager에서 환경변수 로드
# 사용법: source scripts/secrets_load.sh
# gcloud 없으면 .env 폴백
#
# 등록된 secrets (프로젝트: zinc-wares-489921-j3):
#   GEMINI_API_KEY, TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID,
#   SLACK_WEBHOOK_URL, INSTAGRAM_ACCESS_TOKEN, INSTAGRAM_USER_ID

GCP_PROJECT="zinc-wares-489921-j3"
SECRETS=(
  GEMINI_API_KEY
  TELEGRAM_BOT_TOKEN
  TELEGRAM_CHAT_ID
  SLACK_WEBHOOK_URL
  INSTAGRAM_ACCESS_TOKEN
  INSTAGRAM_USER_ID
)

# gcloud 경로 탐색 (OS별)
_find_gcloud() {
  if command -v gcloud &>/dev/null; then
    echo "gcloud"
  elif [ -f "/c/Users/1/AppData/Local/Google/Cloud SDK/google-cloud-sdk/bin/gcloud" ]; then
    echo "/c/Users/1/AppData/Local/Google/Cloud SDK/google-cloud-sdk/bin/gcloud"
  elif [ -f "$HOME/google-cloud-sdk/bin/gcloud" ]; then
    echo "$HOME/google-cloud-sdk/bin/gcloud"
  elif [ -f "/usr/lib/google-cloud-sdk/bin/gcloud" ]; then
    echo "/usr/lib/google-cloud-sdk/bin/gcloud"
  else
    echo ""
  fi
}

GCLOUD=$(_find_gcloud)
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
_env_file="$(dirname "$_script_dir")/.env"

# 1) gcloud CLI 시도
_loaded=0
if [ -n "$GCLOUD" ]; then
  for secret in "${SECRETS[@]}"; do
    value=$("$GCLOUD" secrets versions access latest \
      --secret="$secret" \
      --project="$GCP_PROJECT" 2>/dev/null) || continue
    [ -z "$value" ] && continue
    export "$secret=$value"
    _loaded=$((_loaded + 1))
  done
fi

# 2) gcloud 실패 시 Python ADC 폴백 (ADC 구성된 기기에서 작동)
if [ "$_loaded" -eq 0 ] && command -v python3 &>/dev/null; then
  _py_exports=$(python3 - <<'PYEOF' 2>/dev/null
import sys, os, json, base64, urllib.request
try:
    import google.auth, google.auth.transport.requests
    creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    creds.refresh(google.auth.transport.requests.Request())
    token = creds.token
    project = "zinc-wares-489921-j3"
    secrets = ["GEMINI_API_KEY","TELEGRAM_BOT_TOKEN","TELEGRAM_CHAT_ID",
               "SLACK_WEBHOOK_URL","INSTAGRAM_ACCESS_TOKEN","INSTAGRAM_USER_ID"]
    for s in secrets:
        if os.environ.get(s): continue
        url = (f"https://secretmanager.googleapis.com/v1/projects/{project}"
               f"/secrets/{s}/versions/latest:access")
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                d = json.loads(r.read())
                v = base64.b64decode(d["payload"]["data"]).decode()
                if v: print(f"export {s}='{v}'")
        except: pass
except: pass
PYEOF)
  if [ -n "$_py_exports" ]; then
    eval "$_py_exports"
    _loaded=$(echo "$_py_exports" | wc -l | tr -d ' ')
    echo "[secrets] Python ADC에서 ${_loaded}개 로드됨 (프로젝트: $GCP_PROJECT)"
  fi
fi

# 3) .env 폴백 (미설정 변수 보완용)
if [ -f "$_env_file" ]; then
  set -o allexport
  # shellcheck disable=SC1090
  source "$_env_file"
  set +o allexport
fi

if [ "$_loaded" -gt 0 ]; then
  echo "[secrets] GCP에서 ${_loaded}개 로드됨 (프로젝트: $GCP_PROJECT)"
elif [ -f "$_env_file" ]; then
  echo "[secrets] .env 폴백: $_env_file"
else
  echo "[secrets] WARN: GCP 로드 실패 + .env 없음 — 환경변수 미설정"
fi
