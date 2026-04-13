# Device Manifest — 기기 전용 파일 목록

이 목록의 파일은 **SCP/직접 복사 금지**. 반드시 `sync.sh` 또는 `patch_hooks.py`를 통해 관리.

## 절대 교차 배포 금지

| 파일 | 이유 |
|---|---|
| `~/.claude/settings.local.json` | 기기 전용 훅(nah_guard 등), 권한 허용 목록 |
| `~/.claude.json` | MCP 설정, API 키, project-level 설정 |
| `~/CLAUDE.md` | 경로가 기기별로 다름 — 반드시 `sync.sh`로 배포 |

## 기기별 특이사항

### Windows (`DESKTOP-UT6PQ7D`)
- `settings.local.json`: nah_guard.py 훅 (Python 절대경로), Windows statusline
- `.claude.json` mcpServers: stitch-mcp, gemini-nanobanana-mcp에 `cmd /c` 래퍼 필요
- `.claude.json` projects: `C:/Users/1` 키로 google-workspace MCP 등록
- `~/bin/gws.py`: google-workspace 토글 스크립트
- PowerShell 7 프로필: `~/OneDrive/문서/PowerShell/Microsoft.PowerShell_profile.ps1`
  - `proj` 함수 (프로젝트 선택 + worktree 관리, `Pick-Menu` 커스텀 UI)
  - 백업/원본: `config/powershell_profile.ps1`
- Global gitignore: `~/.gitignore_global` → 백업: `config/gitignore_global`

### Mac 공통 (MacAir / M1 / M4)
- `settings.json`: nah_guard 없음, guard.sh + WebSearch 차단 있음
- MCP: `cmd /c` 래퍼 불필요
- `proj` 함수: `config/proj.zsh` → `~/.zshrc`에서 source
  - 백업/원본: `config/proj.zsh` (fzf + jq 기반, macOS `stat -f %m`)

### M1 (`luma2s-Mac-mini.local`)
- content-automation: `~/Desktop/content-automation/` (Desktop 위치 유지)
- vault: `~/vault/` (MCP obsidian-vault 소스)

### M4 (`luma3ui-Macmini.local`)
- 유저명 `luma3` (MacAir/M1은 `luma2`)

## 안전하게 교차 배포 가능한 파일

| 파일/경로 | 방법 |
|---|---|
| `~/.claude/commands/*.md` (skills) | `sync.sh` 또는 boot 자동 배포 |
| `~/projects/agent-orchestration/` 전체 | `git pull` |
| `~/CLAUDE.md` | `sync.sh`만 (SCP 직접 금지) |
| `~/.claude/settings.json` 공통 훅 | `patch_hooks.py` |
