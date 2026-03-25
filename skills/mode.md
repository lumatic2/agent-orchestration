# Mode

모드 전환 요청을 처리한다.

## 실행

- `$ARGUMENTS`가 있으면: `bash ~/projects/agent-orchestration/scripts/orchestrate.sh --mode $ARGUMENTS`
- `$ARGUMENTS`가 없으면:
  1. `bash ~/projects/agent-orchestration/scripts/orchestrate.sh --mode` 실행
  2. 출력된 모드 목록을 보여주고 사용자에게 선택 요청

## 전환 후 안내: Self-Execution Guard

- `full`: 50줄/3파일 이상 → Codex, 리서치 → Gemini
- `solo`: 제한 없음 — Claude가 모든 작업 직접 수행
- `research`: 200줄/6파일까지 Claude 직접, Codex는 ultra만
- `code`: 50줄/3파일 이상 → Codex, light/default 리서치 Claude 직접
- `conserve-gemini`: 기본 guard + light/default 리서치 → ChatGPT
- `conserve-codex`: 200줄/8파일까지 Claude 직접, Codex는 high/ultra만
