# 시스템 설정 레퍼런스

## 기기별 시스템 가용성 (2026-03-10)

| 시스템 | Mac mini M1 | Windows | 비고 |
|---|---|---|---|
| Claude Code + MCP | ✅ | ✅ | |
| Obsidian vault MCP | ✅ (로컬) | ✅ (SSH→M1) | 4대 설치 완료 |
| Google Drive (개인) | ✅ ~/Library/CloudStorage/ | ❓ | |
| Figma MCP | ✅ (재시작 필요) | ❌ | |

## SSH 접속 정보 (2026-03-10)

| 별칭 | IP (Tailscale) | 사용자 |
|---|---|---|
| windows | 100.103.17.19 | 1 |
| macair | 100.87.7.85 | luma2 |
| m1 (mini) | 100.114.2.73 | luma2 |
| m4 | 100.100.79.12 | luma3 |

```bash
scp /path/file.pdf windows:Desktop/file.pdf
ssh windows "dir Desktop"
```

## OpenClaw 파이프라인 (2026-03-10)

**구조**: 텔레그램 → OpenClaw(라우터) → Claude Code → 결과 텔레그램 전송
- 설정: `~/.openclaw/openclaw.json`
- 주 모델: `moonshot/moonshot-v1-32k`, fallback: `kimi-k2.5`
- 위임: `delegate_to_claude` 툴 → `claude --dangerously-skip-permissions "작업"`

## 에이전트 확장

| 에이전트 | 스크립트 | 용도 |
|---|---|---|
| 이미지 생성 | `scripts/image_agent.sh` | DALL-E 3 / Midjourney 프롬프트 생성 |
| 전문직 AI | `scripts/expert_agent.sh [doctor\|lawyer\|tax]` | 전문가 페르소나 |
| 영상 편집 | `scripts/video_edit.sh` | FFmpeg 자동화 |
| 콘텐츠 파이프라인 | `scripts/content_pipeline.sh` | 소설/책/논문 |
| 회계사 AI | `scripts/tax_agent.sh` | 조특법 R&D/고용세액공제 전문 |

## 새 기기 셋업 순서
```bash
git pull
bash scripts/sync.sh

# Notion MCP
claude mcp add --scope user notion-personal -- npx -y @notionhq/notion-mcp-server

# Obsidian vault MCP
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

## CLI 과금 구조

| CLI | 인증 | 과금 |
|---|---|---|
| Gemini CLI | OAuth (Google 계정) | **무료** — Gemini Advanced 구독 내 |
| Codex CLI | OAuth (OpenAI 계정) | **무료** — ChatGPT Pro 구독 내 |

## GitHub 트렌드 자동 수신 (2026-03-12)
- **스케줄**: launchd `com.luma3.github-trends` — 매주 월 09:00
- **흐름**: `gh api` → Gemini 분류 → `reports/github-trends-YYYY-MM-DD.md` → 텔레그램
- **적용**: `/github-trends` 실행

## 통합 지식베이스

| 소스 | 방법 |
|---|---|
| 회사 Notion | `NOTION_TOKEN=$COMPANY_NOTION_TOKEN python3 ~/notion_db.py` |
| 로컬 PDF | Claude `Read` 도구 직접 |
| Google Drive | MCP `search_drive_files` (yusung8307@gmail.com) |
| 대용량 멀티문서 | `orchestrate.sh gemini` 위임 |
| Obsidian | `~/vault/` 직접 Read |

## 2026-03-08 실전 검증 패턴
- **Gemini 병렬 디스패치**: 3개 동시 → 각 5~10분 완료
- **Notion MCP vs notion_db.py**: MCP는 회사 워크스페이스만. 개인은 notion_db.py 필수
- **M1 헤드리스 자동화**: OpenClaw → SSH → Windows/MacBook Air 완전 작동
