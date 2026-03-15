# Slack ↔ Claude Code 봇 (2026-03-13)

**목적**: 플랜바이 팀 전체가 Slack에서 Claude Code 사용 — 문서·슬라이드 생성, 회사 데이터 조회, 업무 자동화
**레포**: `~/projects/claude-code-slack-bot/` (원본: mpociot/claude-code-slack-bot)

## 완료된 설정
- Slack 토큰 3개 `.env`에 입력 완료
- Node v24.14.0 필수 (v25는 CLI 호환 오류)
- `@anthropic-ai/claude-code` v1.0.128
- `permissionMode: bypassPermissions`
- DM 세션 키 안정화 (ts 제거)
- `SLACK_BOT=1` 환경변수 → 글로벌 CLAUDE.md의 --boot 스킵
- `BASE_DIRECTORY=/Users/luma2/projects/claude-code-slack-bot/`

## 설정 파일 상태
| 파일 | 상태 |
|---|---|
| `.env` | ✅ Slack 토큰 입력됨 |
| `mcp-servers.json` | ⚠️ COMPANY_NOTION_TOKEN 필요 |
| `templates/templates.yaml` | ✅ 슬라이드 2종 + 문서 3종 |
| `CLAUDE.md` | ✅ 회사 컨텍스트 + Notion DB ID |

## 남은 작업
1. **COMPANY_NOTION_TOKEN** → `mcp-servers.json`에 입력
2. Phase 2: Google Workspace MCP 추가
3. Phase 3: 슬라이드·문서 HTML 템플릿 작성

## 실행
```bash
NODE24="v24.14.0"
export PATH="$HOME/.nvm/versions/node/$NODE24/bin:$PATH"
cd ~/projects/claude-code-slack-bot
unset CLAUDECODE ANTHROPIC_API_KEY
npm run dev
```

## 아키텍처
```
Slack → Slack Bot (Socket Mode, Mac mini)
  → Claude Code SDK
  → MCP: notion-company, obsidian-vault, (google-workspace 예정)
  → 로컬: company-vault, templates, slides_config.yaml
```
