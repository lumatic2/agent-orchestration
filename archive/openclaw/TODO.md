# OpenClaw — 재구조화 필요

현재 문제:
- bridge.sh가 폐기된 orchestrate.sh에 의존 → 작동 불가
- TOOLS.md의 delegate_to_codex/gemini도 old bridge.sh 경로 참조

재구조화 방향:
- bridge.sh: orchestrate.sh 대신 Skill("codex:rescue") / gemini-companion.mjs 호출로 교체
- TOOLS.md: 경로 및 명령어 업데이트
- Telegram 수신 → 라우팅 → Codex/Gemini 위임 흐름은 유효함
