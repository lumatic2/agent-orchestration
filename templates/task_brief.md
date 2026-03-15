# Task Brief

## Goal
[1문장: "무엇을" 달성하는지만. 배경/이유 불필요]

## Scope
- Modify: [수정 허용 파일/디렉터리 — 절대경로]
- Read-only: [참조만 허용, 수정 금지 파일]
- No-touch: [절대 건드리지 말 것 — 명시적 금지 영역]

## Context Budget
- MUST load: [반드시 읽어야 할 파일 — 3개 이하]
- MAY load: [필요 시에만 — 탐색 후 판단]
- DO NOT load: [읽지 말 것 — 무관하거나 너무 큰 파일]

## Stop Triggers (즉시 멈추고 보고)
- [ ] Scope 밖 파일을 수정해야 할 것 같을 때
- [ ] 테스트 2회 연속 실패 시
- [ ] 아키텍처 결정이 필요할 것 같을 때
- [ ] [태스크별 추가 조건]

## Constraints
- [금지] 리팩터링 금지. 필요한 최소 변경만.
- [금지] 스코프 밖 파일 수정 금지. 필요하면 멈추고 보고.
- [허용/금지] API 변경 허용/금지
- [스타일] 기존 프로젝트 컨벤션 따를 것

## Execution Order
1. **탐색**: 관련 파일 읽기/검색으로 현재 상태 파악
2. **수정**: 필요한 최소 변경 실행
3. **검증**: Done Criteria의 커맨드 실행하여 확인

## Done Criteria
- [ ] `[검증 커맨드]` 실행 → pass (예: `pytest -q`, `npm test`, `bash tests/run_tests.sh`)
- [ ] [구체적 조건 — 예: "TypeScript 에러 0개", "빌드 성공"]

## Output Format
변경 요약은 **동작 변화** 중심으로 5줄 이내:
1. 변경 파일 목록
2. 동작 변화 요약 (before → after)
3. 검증 결과 (pass/fail + 실패 시 로그 요약)
