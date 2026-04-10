# Tools

## Enabled
- bash_exec
- file_read
- web_search

## Disabled
- system_shutdown
- registry_edit

---

## Telegram

bot_token_env: TELEGRAM_BOT_TOKEN
default_chat_id_env: TELEGRAM_CHAT_ID
notify_on:
  - task_complete
  - task_failed

### send_telegram_file
description: "생성된 PDF 파일을 Telegram으로 전송"
command: bash ~/Desktop/agent-orchestration/scripts/telegram-send.sh "{file_path}" "{caption}"

### send_telegram_message
description: "Telegram으로 텍스트 메시지 전송"
command: bash ~/Desktop/agent-orchestration/scripts/telegram-send.sh --message "{text}"

---

## Custom Tools

### make_slides
description: "주제를 받아 슬라이드 PDF를 생성하고 Telegram으로 전송 (gen-brief→Gemini리서치→Codex HTML→PDF렌더→전송 전 파이프라인)"
command: bash ~/Desktop/agent-orchestration/scripts/slides-bridge.sh "{topic}" 9 telegram

### upload_to_notion
description: "PDF 파일을 Notion 슬라이드 페이지에 업로드"
command: bash ~/Desktop/agent-orchestration/scripts/notion-upload.sh "{file_path}" --title "{title}"

### delegate_to_codex
description: "코드 작업을 Codex에 위임 (50줄 이상, 4파일 이상)"
command: bash ~/Desktop/agent-orchestration/scripts/bridge.sh codex "{task}" "{name}"

### delegate_to_gemini
description: "리서치 및 문서 분석을 Gemini에 위임"
command: bash ~/Desktop/agent-orchestration/scripts/bridge.sh gemini "{task}" "{name}"
