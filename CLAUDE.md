# agent-orchestration

> Claude/Codex/Gemini 멀티에이전트 오케스트레이션 시스템.

## 기술 스택

- Bash 운영 스크립트 (`scripts/*.sh`)
- Python 파이프라인/대시보드 코드 (`pipeline/`, `dashboard/`)
- Python 3.9 타겟 린트 (`pyproject.toml`의 `ruff` 설정)
- Markdown 기반 운영 문서/규칙 (`README.md` 등)

## 프로젝트 구조

- `adapters/`: 에이전트별 설정 소스 (`claude`, `codex`, `gemini`)
- `agents/`: 에이전트별 런타임 관련 파일
- `scripts/`: 오케스트레이션/동기화/가드 스크립트
- `pipeline/`: 리서치 파이프라인 Python 코드
- `dashboard/`: 대시보드 앱 실행 코드 (`run.sh`, `app.py`)
- `context/`, `docs/`: 운영 컨텍스트/문서
- `config/`, `config/`: 환경/도구 설정 스크립트
- `data/`, `outputs/`, `reports/`: 산출물 저장
- `pyproject.toml`: Ruff 설정

## 개발 명령어

```bash
bash scripts/sync.sh --check     # adapter 동기화 검증
bash scripts/sync.sh             # adapter → ~/CLAUDE.md, ~/.codex/, ~/.gemini/ 배포
bash dashboard/run.sh            # 대시보드 실행

# 다른 프로젝트 루트에서 Codex용 AGENTS.md stub 생성 (CLAUDE.md 자동 참조)
bash ~/projects/agent-orchestration/scripts/init-project-agents.sh
```

> 기기별 수동 설치 파일(codex 래퍼 등)은 `scripts/device/` 참조.

> `scripts/orchestrate.sh`는 폐기 경로 (이전 큐잉 시스템). 현재는 글로벌 CLAUDE.md의 Self-Execution Guard 사용.

## 작업 방식

- 새 기능 → 항상 계획 먼저, 구현 나중
- Codex/Gemini 위임 규칙은 글로벌 `~/CLAUDE.md`의 Self-Execution Guard 참조 (이 repo의 `adapters/claude_global.md`가 원본)
- adapter 수정 후 반드시 `bash scripts/sync.sh` 실행하여 ~/CLAUDE.md에 배포

## 인프라 보호 파일 (read-only)

다음 파일은 **read-only**다. 어떤 에이전트(Claude/Codex/Gemini)든 "고치자" "디버그하자" 같은 동기로도 수정 금지. 수정 필요 시 사용자에게 별도 승인 요청 후 진행한다:

- `scripts/sync.sh`
- `scripts/guard.sh`
- `scripts/orchestrate.sh` (폐기 경로 — 보존 목적)
- `adapters/claude_global.md`
- `adapters/codex_home.md`, `adapters/gemini.md`
- `agent_config.yaml`, `ROUTING_TABLE.md` (있을 경우)

이 룰을 위반해야 할 것 같으면 **중단하고 보고**.