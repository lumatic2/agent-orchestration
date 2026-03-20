# TOKEN_DISCIPLINE.md

## Daily Checklist (실측 기반)

### 1) 세션 시작
- [ ] `orchestrate.sh --boot` 실행
- [ ] 오늘 날짜 로그 파일 생성/확인
- [ ] `agent_config.yaml`의 limits 섹션 최신값 확인

### 2) Claude 사용 규율 (Max 20x)
- [ ] Claude는 판단/라우팅/검수만 수행
- [ ] 4+ 파일 또는 50+ 줄 구현은 즉시 Codex로 위임
- [ ] 리서치가 포함되면 즉시 Gemini로 위임

### 3) Codex 사용 규율 (ChatGPT Pro)
- [ ] 코딩/리팩터/디버깅/테스트 루프는 Codex heavy 우선
- [ ] 단순 수정/탐색은 codex-spark 우선
- [ ] 동일 태스크 재시도 시 모델 업그레이드보다 태스크 분할 우선

### 4) Gemini 일일 한도 관리 (2026-03-20 실측 반영)
- [ ] Flash: **300 prompts/day**
- [ ] Pro: **100 prompts/day**
- [ ] 기본값은 Flash
- [ ] Pro는 심층 분석(교차검증/장문 종합/전략 결정)에만 사용

### 5) Gemini Pro 사용 허용 조건
- [ ] 독립 리서치 섹션 4개 이상
- [ ] 복수 문서 교차분석 + 모순 탐지 필요
- [ ] 장기 의사결정(아키텍처/전략) 근거 정리 필요
- [ ] 50페이지 이상 문서의 심층 종합 필요

### 6) 종료 전 점검
- [ ] 오늘 사용량을 간단히 기록(Flash/Pro 대략치)
- [ ] 다음 세션 인계가 필요한 항목만 SHARED_MEMORY에 반영
- [ ] 큐 상태(`--status`) 확인 후 미완료 태스크를 명시

## Daily Operating Rule
- 수치/모델 변경은 `agent_config.yaml`만 수정한다.
- 이 문서는 실행 체크리스트만 유지한다.