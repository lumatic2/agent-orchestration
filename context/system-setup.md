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
| Obsidian vault | MCP `mcp__obsidian-vault__*` (m1:~/vault/) |
| 대용량 멀티문서 | `orchestrate.sh gemini` 위임 |

## 텔레그램 봇

**구조**: Galaxy → Telegram → claude-code-telegram (@Floatery_bot) → Claude Code → 결과 텔레그램 전송
- M1 `~/projects/claude-code-telegram/`

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
