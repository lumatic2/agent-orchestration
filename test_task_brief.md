# Task Brief Example

## Goal
Fix a typo in the `README.md` file.

## Scope
- Modify: `/Users/luma3/Desktop/agent-orchestration/README.md`
- Read-only: None
- No-touch: None

## Constraints
- [금지] 리팩터링 금지. 필요한 최소 변경만.
- [금지] 스코프 밖 파일 수정 금지. 필요하면 멈추고 보고.
- [스타일] 기존 프로젝트 컨벤션 따를 것

## Execution Order
1. **탐색**: `README.md` 파일 읽기
2. **수정**: 오타 수정
3. **검증**: `README.md` 파일 내용 확인

## Done Criteria
- [ ] The typo "welcom" is replaced with "welcome" in `README.md`.

## Output Format
변경 요약은 **동작 변화** 중심으로 5줄 이내:
1. 변경 파일 목록
2. 동작 변화 요약 (before → after)
3. 검증 결과 (pass/fail + 실패 시 로그 요약)
