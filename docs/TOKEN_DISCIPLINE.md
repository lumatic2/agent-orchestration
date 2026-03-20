# Token Discipline Checklist

## 매 세션 시작
- [ ] `orchestrate.sh --boot` 실행
- [ ] 현재 모델 확인: `/context` → "Model: Sonnet"이 맞는가?
- [ ] Plan Mode 피하기 — Brief 작성 후 Codex 위임

## 작업 판단 (3초 체크)
- [ ] 4+ 파일 또는 50+ 줄? → Codex 위임 (당신이 Brief만 쓰기)
- [ ] 웹 검색 필요? → Gemini 위임 (당신이 결과 정리만)
- [ ] 단순 수정 1-3파일? → Sonnet 직접 (판단 불필요)
- [ ] 전략/시스템? → Opus 또는 Codex 위임

## 금지 패턴
- ❌ Sonnet으로 "버그 고쳐줘" (→ Codex)
- ❌ Sonnet으로 "이 파일 50줄 추가해줘" (→ Codex)
- ❌ Claude가 CLAUDE.md/ROUTING_TABLE.md 다시 읽기 (한 번만 로드)
- ❌ "결과 정리해줄래"를 반복 (→ Gemini 바로 위임)

## 관찰 지표 (주 1회 확인)
- `~/projects/agent-orchestration/logs/` 최신 파일 크기
  - Codex 1M+: 좋음 (캐싱 효율 확인)
  - Claude 500K+: 위험 (Brief 재읽기 의심)
- Gemini 사용: 200 → 목표 500+/day
- Codex 캐시 hit율: `cached_input_tokens / input_tokens` 85% 이상?
