# OpenClaw 설치 및 설정 가이드

> OpenClaw: 자율 AI 에이전트 프레임워크 + ClawHub 스킬 마켓플레이스
> 작성 기준: 2026-03-08 | 검증 환경: macOS (Apple Silicon)

---

## 1. 설치 방법

### 방법 A: npm (권장)

```bash
# OpenClaw CLI 설치
npm install -g @openclaw/cli

# 설치 확인
openclaw --version
```

### 방법 B: npx (설치 없이 즉시 실행)

```bash
# 설치 없이 바로 실행 (매번 최신 버전 사용)
npx @openclaw/cli@latest init
```

### 방법 C: Git clone (개발/커스터마이징용)

```bash
git clone https://github.com/openclaw/openclaw.git ~/.openclaw
cd ~/.openclaw
npm install
npm link   # openclaw 명령어 전역 등록
```

### 방법 D: Homebrew (macOS)

```bash
brew tap openclaw/tap
brew install openclaw
```

### 의존성 확인

```bash
node --version   # v20 이상 필요
npm --version    # v9 이상 권장
```

---

## 2. 실행 방법

### 대화형 모드 (기본)

```bash
# 기본 실행 — 대화형 프롬프트
openclaw

# 에이전트 이름 지정
openclaw --agent my-agent

# 특정 작업 디렉토리 지정
openclaw --workdir ~/projects/my-project
```

### 헤드리스 / 백그라운드 모드

```bash
# 헤드리스: 단일 명령 실행 후 종료
openclaw --headless --prompt "오늘 할 일 목록 정리해줘"

# 백그라운드 데몬으로 실행 (nohup)
nohup openclaw --daemon > ~/.openclaw/logs/daemon.log 2>&1 &

# PID 저장
echo $! > ~/.openclaw/daemon.pid

# 데몬 종료
kill $(cat ~/.openclaw/daemon.pid)
```

### 자동 승인 모드 (--yolo)

```bash
# 모든 도구 호출 자동 승인 (신뢰할 수 있는 환경에서만)
openclaw --yolo

# 파이프 입력
echo "파이썬으로 Hello World 작성" | openclaw --yolo --headless
```

---

## 3. Kimi 모델 연결 설정 (Moonshot API)

### 3-1. API 키 발급

1. Moonshot AI 플랫폼(platform.moonshot.cn) 로그인
2. [API Keys] 메뉴 → [Create API Key]
3. 키 복사 후 안전한 곳에 보관

### 3-2. 환경 변수 설정

```bash
# ~/.zshenv 또는 ~/.bashrc에 추가
echo 'export MOONSHOT_API_KEY="sk-xxxxxxxxxxxxxxxxxxxx"' >> ~/.zshenv
source ~/.zshenv
```

### 3-3. OpenClaw 에이전트 설정 파일 구성

에이전트는 작업 디렉토리의 마크다운 파일로 동작을 정의합니다.

**`SOUL.md`** — 에이전트 목적 및 역할 정의

```markdown
# Agent Soul

## Role
You are a productivity assistant integrated with Claude Code orchestration.

## Mission
- Automate repetitive tasks
- Delegate heavy work to Codex/Gemini
- Maintain SHARED_MEMORY.md after significant tasks

## Constraints
- Never modify files outside assigned scope
- Report blockers instead of bypassing them
```

**`IDENTITY.md`** — 모델 및 API 설정

```markdown
# Identity

## Model
provider: moonshot
model: moonshot-v1-128k
api_key_env: MOONSHOT_API_KEY
base_url: https://api.moonshot.cn/v1

## Fallback
fallback_provider: openai
fallback_model: gpt-4o
```

**`TOOLS.md`** — 허용 도구 목록

```markdown
# Tools

## Enabled
- bash_exec
- file_read
- file_write
- web_search

## Disabled
- system_shutdown
- registry_edit
```

### 3-4. 연결 테스트

```bash
openclaw --headless --prompt "안녕, 지금 몇 시야?" --agent ./
```

---

## 4. Telegram 채널 연결 방법

### 4-1. Telegram Bot 생성

1. Telegram에서 `@BotFather` 검색
2. `/newbot` 명령 → 봇 이름 및 username 설정
3. 발급된 토큰 복사: `7xxxxxxxxx:AAF-xxxxxxxxxxxxxxxxxx`

### 4-2. 채널 Chat ID 확인

```bash
# 봇을 채널에 초대한 후 아래 URL 접근
# (봇 토큰으로 업데이트 조회)
curl "https://api.telegram.org/bot<TOKEN>/getUpdates"

# 응답 JSON에서 "chat":{"id": -100xxxxxxxxxx} 확인
```

### 4-3. 환경 변수 설정

```bash
echo 'export TELEGRAM_BOT_TOKEN="7xxxxxxxxx:AAF-xxxxxxxxxxxxxxxxxx"' >> ~/.zshenv
echo 'export TELEGRAM_CHAT_ID="-100xxxxxxxxxx"' >> ~/.zshenv
source ~/.zshenv
```

### 4-4. OpenClaw Telegram 스킬 설치

```bash
# ClawHub에서 Telegram 스킬 설치
npx clawhub@latest install telegram-notify

# 또는 수동 설치 (보안 감사 후 권장)
npx clawhub@latest inspect telegram-notify   # 코드 먼저 확인
npx clawhub@latest install telegram-notify   # 이상 없으면 설치
```

### 4-5. 알림 설정 (`TOOLS.md`에 추가)

```markdown
## Telegram
bot_token_env: TELEGRAM_BOT_TOKEN
default_chat_id_env: TELEGRAM_CHAT_ID
notify_on:
  - task_complete
  - task_failed
  - rate_limit_hit
```

### 4-6. 테스트

```bash
openclaw --headless --prompt "Telegram으로 '셋업 완료' 메시지 보내줘"
```

---

## 5. Claude Code 위임 연동 (에이전트 오케스트레이션)

### 5-1. 개요

OpenClaw가 수신한 작업을 이 오케스트레이션 시스템의 `orchestrate.sh`를 통해
Claude Code(Codex/Gemini)로 라우팅하는 구조.

```
사용자 → Telegram/CLI
    └→ OpenClaw (수신 + 판단)
           ├→ 경량 작업: Kimi (moonshot-v1-128k) 직접 처리
           ├→ 코드 작업: orchestrate.sh codex "task" name
           └→ 리서치:    orchestrate.sh gemini "task" name
```

### 5-2. 오케스트레이션 브리지 스크립트

`~/.openclaw/bridge.sh` 생성:

```bash
#!/usr/bin/env bash
# OpenClaw → orchestrate.sh 브리지

AGENT_TYPE="${1:-codex}"   # codex | gemini | codex-spark | gemini-pro
TASK="${2}"
TASK_NAME="${3:-openclaw-$(date +%s)}"

ORCH="$HOME/projects/agent-orchestration/scripts/orchestrate.sh"

if [ ! -f "$ORCH" ]; then
  echo "ERROR: orchestrate.sh not found at $ORCH" >&2
  exit 1
fi

bash "$ORCH" "$AGENT_TYPE" "$TASK" "$TASK_NAME"
```

```bash
chmod +x ~/.openclaw/bridge.sh
```

### 5-3. `TOOLS.md`에 브리지 등록

```markdown
## Custom Tools

### delegate_to_codex
description: "50줄 이상 코드 작업을 Codex에 위임"
command: bash ~/.openclaw/bridge.sh codex "{task}" "{name}"

### delegate_to_gemini
description: "리서치 및 문서 분석을 Gemini에 위임"
command: bash ~/.openclaw/bridge.sh gemini "{task}" "{name}"
```

### 5-4. `SOUL.md`에 위임 규칙 추가

```markdown
## Delegation Rules
- 코드 작업 50줄 이상 → delegate_to_codex 사용
- 파일 4개 이상 수정 → delegate_to_codex 사용
- 리서치/문서 분석 → delegate_to_gemini 사용
- 간단한 편집 (1-3파일, 50줄 미만) → 직접 처리
```

### 5-5. 큐 상태 확인 통합

```bash
# OpenClaw 내에서 큐 상태 조회
openclaw --headless --prompt "orchestrate.sh --status 실행해서 결과 알려줘"
```

---

## 6. 자동 시작 설정

### macOS — launchd

`~/Library/LaunchAgents/com.openclaw.agent.plist` 생성:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.openclaw.agent</string>

  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/openclaw</string>
    <string>--daemon</string>
    <string>--yolo</string>
    <string>--agent</string>
    <string>/Users/luma2/.openclaw/agents/main</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>MOONSHOT_API_KEY</key>
    <string>sk-xxxxxxxxxxxxxxxxxxxx</string>
    <key>TELEGRAM_BOT_TOKEN</key>
    <string>7xxxxxxxxx:AAF-xxxxxxxxxxxxxxxxxx</string>
    <key>TELEGRAM_CHAT_ID</key>
    <string>-100xxxxxxxxxx</string>
  </dict>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>/Users/luma2/.openclaw/logs/stdout.log</string>

  <key>StandardErrorPath</key>
  <string>/Users/luma2/.openclaw/logs/stderr.log</string>
</dict>
</plist>
```

```bash
# 로그 디렉토리 생성
mkdir -p ~/.openclaw/logs

# 서비스 등록 및 시작
launchctl load ~/Library/LaunchAgents/com.openclaw.agent.plist

# 상태 확인
launchctl list | grep openclaw

# 서비스 중지
launchctl unload ~/Library/LaunchAgents/com.openclaw.agent.plist

# 로그 실시간 확인
tail -f ~/.openclaw/logs/stdout.log
```

### Linux — systemd

`~/.config/systemd/user/openclaw.service` 생성:

```ini
[Unit]
Description=OpenClaw AI Agent Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/openclaw --daemon --yolo --agent %h/.openclaw/agents/main
Restart=on-failure
RestartSec=10

EnvironmentFile=%h/.openclaw/.env

StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw

[Install]
WantedBy=default.target
```

`~/.openclaw/.env` 생성:

```bash
MOONSHOT_API_KEY=sk-xxxxxxxxxxxxxxxxxxxx
TELEGRAM_BOT_TOKEN=7xxxxxxxxx:AAF-xxxxxxxxxxxxxxxxxx
TELEGRAM_CHAT_ID=-100xxxxxxxxxx
```

```bash
# 서비스 활성화
systemctl --user daemon-reload
systemctl --user enable openclaw
systemctl --user start openclaw

# 상태 확인
systemctl --user status openclaw

# 로그 확인
journalctl --user -u openclaw -f
```

---

## 7. ClawHub 스킬 관리

### 스킬 설치 전 보안 감사 (필수)

ClawHub 스킬의 12~20%에 악성 코드 또는 프롬프트 인젝션 취약점이 보고되었습니다.

```bash
# 설치 전 코드 확인
npx clawhub@latest inspect <skill-slug>

# 검증된 스킬 설치
npx clawhub@latest install <skill-slug>

# 설치된 스킬 목록
npx clawhub@latest list

# 스킬 제거
npx clawhub@latest uninstall <skill-slug>
```

### 권장 스킬 목록

| 스킬 슬러그 | 기능 |
|---|---|
| `telegram-notify` | Telegram 알림 발송 |
| `github` | PR 생성·이슈 관리 |
| `notion` | Notion 페이지 동기화 |
| `playwright` | 브라우저 자동화 |
| `tavily` | AI 최적화 웹 검색 |
| `debug-pro` | 체계적 디버깅 보조 |

---

## 8. 디렉토리 구조 참고

```
~/.openclaw/
├── agents/
│   └── main/
│       ├── SOUL.md         # 에이전트 역할/목적
│       ├── IDENTITY.md     # 모델/API 설정
│       └── TOOLS.md        # 허용 도구
├── logs/
│   ├── stdout.log
│   └── stderr.log
├── bridge.sh               # orchestrate.sh 브리지
├── .env                    # 환경 변수 (Linux용)
└── daemon.pid              # 데몬 PID
```

---

## 9. 트러블슈팅

| 증상 | 확인 사항 |
|---|---|
| `openclaw: command not found` | `npm install -g @openclaw/cli` 재실행, PATH 확인 |
| Moonshot API 401 | `MOONSHOT_API_KEY` 환경 변수 확인, 키 만료 여부 |
| Telegram 메시지 미발송 | 봇이 채널에 추가됐는지 확인, Chat ID 음수(-100...) 여부 |
| launchd 서비스 미시작 | plist 문법 오류: `plutil -lint ~/Library/LaunchAgents/com.openclaw.agent.plist` |
| 스킬 설치 후 이상 동작 | `npx clawhub@latest uninstall <slug>` → 코드 수동 감사 후 재설치 |

---

*이 가이드는 `~/projects/agent-orchestration/` 오케스트레이션 시스템과 함께 사용하도록 설계되었습니다.*
*오케스트레이션 전체 구조: `ORCHESTRATION_SETUP.md` 참조*
