# agent-orchestration

> Claude/Codex/Gemini 멀티에이전트 오케스트레이션 시스템.

## 기술 스택

- Bash 운영 스크립트 (`scripts/*.sh`)
- Python 파이프라인/대시보드 코드 (`pipeline/`, `dashboard/`)
- Python 3.9 타겟 린트 (`pyproject.toml`의 `ruff` 설정)
- Markdown 기반 운영 문서/규칙 (`README.md`, `SHARED_PRINCIPLES.md` 등)

## 프로젝트 구조

- `adapters/`: 에이전트별 설정 소스 (`claude`, `codex`, `gemini`)
- `agents/`: 에이전트별 런타임 관련 파일
- `scripts/`: 오케스트레이션/동기화/가드 스크립트
- `pipeline/`: 리서치 파이프라인 Python 코드
- `dashboard/`: 대시보드 앱 실행 코드 (`run.sh`, `app.py`)
- `context/`, `docs/`: 운영 컨텍스트/문서
- `config/`, `configs/`: 환경/도구 설정 스크립트
- `data/`, `outputs/`, `reports/`: 산출물 저장
- `pyproject.toml`: Ruff 설정

## 개발 명령어

```bash
bash scripts/sync.sh --check
bash scripts/sync.sh
bash scripts/orchestrate.sh codex "task"
bash scripts/orchestrate.sh gemini "research"
bash dashboard/run.sh
```

## 작업 방식

- 새 기능 -> 항상 계획 먼저, 구현 나중
- 50줄+ 코드 작성 -> Codex 위임
- 복잡 리서치 -> Gemini 위임
- 인프라 보호 파일(`scripts/orchestrate.sh`, `scripts/sync.sh`, `scripts/guard.sh` 등) 변경은 별도 승인 후 진행