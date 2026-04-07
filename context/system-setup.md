# 시스템 설정 레퍼런스

> 최종 업데이트: 2026-03-16

---

## 기기 목록

| 별칭 | IP (Tailscale) | 사용자 | 용도 |
|------|---------------|--------|------|
| (현재) Mac Air | — | luma2 | **메인** |
| m1 | 100.114.2.73 | luma2 | Mac mini |
| m4 | 100.100.79.12 | luma3 | M4 Mac |
| windows | 100.103.17.19 | 1 | 집 Windows PC |

## 기기별 가용 기능

| 기능 | Mac Air | Mac mini | M4 | Windows |
|------|---------|----------|----|---------|
| Claude Code | ✅ | ✅ | ✅ | ✅ |
| PDF 렌더 (Playwright) | ✅ | ❌ (Node 없음) | ❌ (Node 없음) | ✅ |
| Gemini CLI | ✅ | ✅ | ✅ | ✅ |
| Obsidian vault MCP | ✅ (SSH→m1) | ✅ (로컬) | ✅ (SSH→m1) | ✅ (SSH→m1) |
| Google Workspace MCP | ✅ | ✅ | ✅ | ✅ |
| nah_guard | ❌ | ❌ | ❌ | ✅ |

## Claude Code 설정 구조 (2026-03-16 기준)

### ~/.claude/CLAUDE.md (글로벌, 4대 공통)
- 한국어 응답, 간결하게
- 모델/Effort 추천 가이드 (질문 복잡도 기반)
- 원본: `adapters/claude_global.md`

### ~/.claude/settings.json

**공통 (Mac 3대)**
- model: sonnet, effortLevel: medium
- hooks: guard.sh, auto-stage, bash_audit, ruff, auto-commit(SCHEDULE.md), auto-pull(SCHEDULE.md), WebSearch 차단
- 원본: `config/mac-settings.json`

**Windows 추가**
- hooks: nah_guard (Bash/Read/Write/Edit/Glob/Grep/mcp)
- statusLine: `~/.claude/statusline.sh`
- 원본: `config/windows-settings.json`

### 설정 재배포 방법 (날아갔을 때)
```bash
bash ~/projects/agent-orchestration/scripts/deploy-settings.sh
# 옵션: all | local | mac | windows
```

## Git 설정 안전성

| 항목 | 위치 | git 영향 |
|------|------|----------|
| settings.json | ~/.claude/ | **없음** (git 외부) |
| CLAUDE.md | ~/.claude/ | **없음** (git 외부) |
| scripts/ 변경사항 | repo 내 | push/pull 대상 — 커밋 완료 |
| pre-commit hook | .git/hooks/ | **없음** (git 외부) — deploy-settings.sh로 복원 |

### pre-commit hook (4대 설치됨)
- `scripts/*.sh` 에 `source env.sh` 누락 시 커밋 차단
- 예외: 커밋 메시지에 `[no-env]` 포함 시 통과

### env.sh (scripts/env.sh)
플랫폼 감지 모듈. 신규 스크립트 작성 시 반드시 포함:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
```
- `SYS_TMP`: 임시 경로 (Windows: AppData/Temp, Mac: /tmp)
- `NODE_PATH`: npm 모듈 경로
- `safe_mktemp prefix [suffix]`: 비 ASCII 안전 mktemp

### 신규 스크립트 생성
```bash
bash scripts/new-script.sh <이름.sh> "설명"
```

## SSH 접속

```bash
ssh m1       # Mac mini
ssh m4       # M4
ssh windows  # Windows (Git Bash — 2026-03-16 변경)
```

**Windows SSH 셸**: PowerShell → Git Bash 변경 완료 (2026-03-16)
- `ssh windows 'bash 명령'` 바로 사용 가능
- PowerShell 필요 시: `ssh windows 'powershell -Command "..."'`

## 레포 경로 (전 기기 동일)

```
~/projects/agent-orchestration
```

## CLI 과금 구조

| CLI | 인증 | 과금 |
|-----|------|------|
| Gemini CLI | OAuth (Google 계정) | **무료** — Gemini Advanced 구독 내 |
| Codex CLI | OAuth (OpenAI 계정) | **무료** — ChatGPT Pro 구독 내 |

## 핵심 스크립트

| 스크립트 | 용도 |
|----------|------|
| `scripts/slides.sh "주제" [N]` | 슬라이드 PDF 생성 (Mac Air / Windows만) |
| `scripts/docs.sh "주제" [type]` | 문서 PDF 생성 (Mac Air / Windows만) |
| `scripts/orchestrate.sh` | Gemini/Codex 위임 오케스트레이터 |
| `scripts/deploy-settings.sh` | ~/.claude/ 설정 전체 배포 |
| `scripts/new-script.sh` | env.sh 포함 스크립트 뼈대 생성 |
| `scripts/guard.sh` | 위험 명령 차단 hook |

## 통합 지식베이스

| 소스 | 방법 |
|------|------|
| 회사 Notion | `NOTION_TOKEN=$COMPANY_NOTION_TOKEN python3 ~/notion_db.py` |
| 개인 Notion | MCP `mcp__claude_ai_Notion__*` |
| Slack | MCP `mcp__claude_ai_Slack__*` |
| Google Workspace | MCP `mcp__google-workspace__*` (yusung8307@gmail.com) |
| Obsidian vault | MCP `mcp__obsidian-vault__*` (m4:~/vault/) |
| 대용량 멀티문서 | `orchestrate.sh gemini` 위임 |

## 텔레그램 봇 (claude-channel)

**구조**: Galaxy → Telegram → @Floatery_bot → claude-plugins-official/telegram MCP → Claude Code (M4) → 결과 응답

**운영 환경 (M4, 2026-04-08 기준)**
- 인증: **claude.ai 계정** (Max plan, $100 extra usage). API/Console 계정 아님.
- 실행: tmux 세션 `claude-channel` (detached)
- 시작 스크립트: `~/projects/agent-orchestration/scripts/start-claude-channel.sh`
- launchd plist: `~/Library/LaunchAgents/com.luma3.claude-channel.plist` (자동 시작/재시작)
- 필수 PATH: `~/.bun/bin`, `~/.nvm/versions/node/v24.14.0/bin`, `/opt/homebrew/bin`
- 페어링: `~/.claude/channels/telegram/access.json` (chat_id allowlist)
- 로그: `~/Library/Logs/claude-channel.log`

**관리**: `/channel` 스킬 사용 (status / logs / restart / attach / fix)

**주의사항**
- 같은 봇 토큰으로 여러 프로세스 polling 시 충돌 → 시작 전 좀비 프로세스 정리 필수
- tmux 세션은 SSH `exit` 시 죽을 수 있음 → 반드시 `Ctrl+B → D`로 detach 또는 detached 모드(`-d`)로 시작
- channels 기능은 claude.ai 인증 전용 (API 계정에서는 작동 안 함)
- telegram 플러그인 0.0.4 이상 필요
- **`claude plugin enable telegram@claude-plugins-official` 상태 필수** — disabled면 MCP 안 뜸
- **bypass permissions 경고**는 시작 스크립트가 자동 동의 (`tmux send-keys '2'`)
- **TELEGRAM_BOT_TOKEN**이 `~/.zshenv`에 있어야 함 (시작 스크립트가 source)

## 다른 텔레그램 봇 (M4 운영)

| 봇 | 토큰 (앞 10자) | 프로젝트 | launchd | 용도 |
|---|---|---|---|---|
| @Floatery_bot (둥둥이) | `8574749488` | claude-channel | `com.luma3.claude-channel` | Claude Code 텔레그램 채널 |
| @Michelin_Chef_bot | `8678722007` | `~/projects/ingredient-bot/` | `com.luma3.ingredient-bot` | 냉장고를부탁해 (식재료 관리) |
| (IT 봇) | `TELEGRAM_BOT_TOKEN_IT` | — | — | 미정 |

**중요**: 봇 코드는 반드시 `load_dotenv(override=True)` 사용 — 그래야 launchd 부모 shell 환경의 토큰이 .env를 덮어쓰지 않음. 무시하면 봇이 엉뚱한 토큰으로 실행되어 polling 충돌 발생.

## 새 기기 셋업 순서

```bash
# 1. 레포 클론
git clone git@github.com:Mod41529/agent-orchestration.git ~/projects/agent-orchestration
cd ~/projects/agent-orchestration

# 2. 설정 배포 (Mac의 경우)
bash scripts/deploy-settings.sh local

# 3. ruff 설치
pip3 install ruff

# 4. MCP 서버 (필요 시)
# Notion/Slack/Google Workspace는 Anthropic 빌트인 플러그인 사용
# Obsidian vault:
python3 -c "
import json, os
path = os.path.expanduser('~/.claude.json')
config = json.load(open(path)) if os.path.exists(path) else {}
config.setdefault('mcpServers', {})['obsidian-vault'] = {
    'type': 'stdio', 'command': 'ssh',
    'args': ['m1', 'source ~/.nvm/nvm.sh && npx -y @bitbonsai/mcpvault@latest ~/vault']
}
json.dump(config, open(path, 'w'), indent=2)
"
```
