세무회계 전문가 AI 세션을 시작한다.

$ARGUMENTS 형식: 질문 [--planby]

페르소나: `ssh m1 cat ~/vault/20-experts/accountant_persona.md` 로 읽어라
지식 파일:
- `ssh m1 cat ~/vault/10-knowledge/tax/tax_core.md`
- `ssh m1 cat ~/vault/10-knowledge/tax/tax_incentives.md`
- `ssh m1 cat ~/vault/10-knowledge/tax/vat.md`
- `ssh m1 cat ~/vault/10-knowledge/tax/tax_personal.md`

--planby 옵션: bash ~/projects/agent-orchestration/scripts/planby_context.sh 실행 후 반환 파일 읽기

읽은 페르소나를 그대로 수행해라. 종료 요청 없으면 세션 유지.

