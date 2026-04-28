# AGENTS.md — agent-orchestration

> Codex 프로젝트 스코프 규칙. 생성: scripts/init-project-agents.sh

## 공통 원칙

공통 원칙(Identity, Behavioral Rules, Infrastructure Protection, Worker Agent 규칙)은
홈 스코프 `~/.codex/AGENTS.md` 에서 이미 로드됐다. 여기서는 중복하지 않는다.

## 프로젝트 규칙

이 프로젝트의 상세 규칙·구조·관례는 같은 디렉토리의 `CLAUDE.md`에 있다.
**세션 시작 시 반드시 `./CLAUDE.md` 와 `./ROADMAP.md`(있으면)를 읽고 시작할 것.**

- `CLAUDE.md`: 프로젝트 기술 스택, 구조, 개발 명령어, 보호 파일 / 금지 사항, 기타 이 프로젝트 고유의 작업 방식
- `ROADMAP.md`: 마일스톤·진행 상태·다음 할 일 (체크리스트). 작업 착수 전 현재 진행 상황 파악용

`CLAUDE.md`의 내용 중 "Claude 전용"(Skill 도구 호출 규칙, 모델 라우팅 등) 문구는
무시해도 되지만, 프로젝트 구조·규칙은 그대로 따른다.
