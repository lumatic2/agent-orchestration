# REPO_LAYOUT — 폴더 정리 규칙

> 이 레포의 폴더 의도와 라이프사이클. 새 파일·폴더 추가 시 여기 규칙에 맞춰 배치.

## 추적되는 폴더 (committed)

| 폴더 | 역할 | 추가 규칙 |
|---|---|---|
| `adapters/` | 에이전트 설정 SoT 3종 (`claude_global.md` / `codex_home.md` / `gemini.md`) | `sync.sh`만 이 폴더를 배포 소스로 본다. 새 에이전트 추가 시 여기에 |
| `scripts/` | 운영 스크립트 (.sh / .py / hook) | 사용자가 호출하는 wrapper, sync, dispatch, hook. 기기별 절대경로 의존 스크립트는 `scripts/device/` 안에 |
| `config/` | 환경·도구 설정 파일 (settings.json 베이스, statusline, mcp_setup 등) | 개인 ID·토큰이 들어가는 파일은 `.gitignore`로 제외 (`config/notion_pages.conf` 패턴) |
| `docs/` | 외부에 보일 수 있는 운영 문서 (roadmap, 사용 가이드) | 초안·세션 로그는 여기 두지 말고 `archive/` 또는 vault |
| `context/` | 로컬에서만 의미 있는 상세 컨텍스트 | 기기별 statusline 등은 `.gitignore` |
| `examples/` | 재사용 가능한 프롬프트·템플릿 | 한 번 쓰고 버릴 출력은 여기 두지 말 것 |

루트 SoT 파일: `CLAUDE.md`, `AGENTS.md`, `README.md`, `ROADMAP.md`, `ROUTING_TABLE.md`, `USER_CONTEXT.md`, `agent_config.yaml`, `pyproject.toml`.

## 무시되는 폴더 (`.gitignore`)

| 폴더 | 역할 |
|---|---|
| `archive/` | WIP, legacy, 세션 로그, 폐기된 파일의 무덤. 로컬에만 보관 |
| `tmp/` | 작업 중 임시 파일 (1회성 비교 스크립트, 초안 등) |
| `data/` · `outputs/` · `reports/` | 파이프라인 산출물 |
| `queue/T*/`, `tasks/`, `briefs/`, `projects/` | 런타임 상태 |
| `.venv*/`, `node_modules/`, `__pycache__/` | 의존성 |

## 라이프사이클

**legacy / 폐기**: `git mv`가 아닌 **shell `mv`** 로 `archive/`에 옮긴다 (`archive/`는 gitignored이므로 git에는 deletion으로 기록 → 다른 기기는 클린 삭제, 로컬엔 사본 보존).

**임시 작업**: `tmp/`에 둔다. 루트에 `tmp_*.py` 같은 stray 파일을 만들지 않는다. `.gitignore`가 `tmp_*` 패턴을 잡아주긴 하지만 루트 정리 차원에서.

**docs vs context**: 다른 사람·다른 기기에서도 의미 있으면 `docs/`. 이 기기에서만 / 개인 메모성이면 `context/` 또는 vault.

**기기 마이그레이션**: 폴더 삭제·이동 시 다른 기기에도 자동 반영하려면 `scripts/sync.sh`에 idempotent migration 함수를 추가한다 (예: `migrate_codex_legacy`). 사용자가 수동 정리 안 해도 되도록.

## SoT → 배포 매핑

| SoT (committed) | 배포 destination | 도구 |
|---|---|---|
| `adapters/claude_global.md` + `USER_CONTEXT.md` | `~/CLAUDE.md` | `sync.sh deploy_claude` |
| `adapters/codex_home.md` + `USER_CONTEXT.md` + (Custom Commands index) | `~/AGENTS.md` | `sync.sh deploy_codex_home` |
| `adapters/gemini.md` | `~/.gemini/GEMINI.md` | `sync.sh deploy_gemini` |
| `config/settings_common.json` | `~/.claude/settings.json` (초기화 전용, 이후 patch_hooks.py로 공통 훅만 갱신) | `sync.sh deploy_claude` |
| `scripts/hooks/*.{py,sh}` | `~/.claude/hooks/` | `sync.sh deploy_claude` |
| `scripts/device/{job-watcher.mjs, job-watcher-inject.py}` | `~/.claude/hooks/` | `sync.sh deploy_claude` (기기 비의존 device 파일만 자동) |
| `config/statusline.sh` | `~/.claude/statusline.sh` | `sync.sh deploy_claude` |

배포본은 직접 편집 금지 — 다음 sync 때 덮어쓴다. SoT만 편집한다.

## 인프라 보호 read-only

`~/CLAUDE.md` (== `adapters/claude_global.md`)에 명시된 read-only 목록은 어떤 에이전트도 무단 수정 금지. 수정 필요 시 사용자에게 별도 승인 요청.
