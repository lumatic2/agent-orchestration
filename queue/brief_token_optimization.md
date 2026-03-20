# Task: 오케스트레이션 토큰 절약 + 워커 활용률 극대화

## 배경
지난 4시간 동안 Claude Code Pro에서 토큰이 빠르게 소진됨.
분석 결과:
- Claude가 매번 full context (CLAUDE.md, ROUTING_TABLE.md 등) 재읽기
- Plan Mode 사용 금지 (Extended Thinking = token multiplier)
- Codex/Gemini 한도는 충분하지만 사용률 낮음 (캐싱 효율 80%+)

목표: Claude → Codex/Gemini로 역할 시프트. Claude는 "뇌 중 판단만"

---

## 작업 1: CLAUDE.md 모델 라우팅 규칙 강화

파일: `C:/Users/1/CLAUDE.md` (또는 원본 `~/projects/agent-orchestration/adapters/claude_global.md`)

### 현재 문제
```
- Sonnet + low~medium: 파일 조회/편집, 간단한 스크립트, 정보 조회
- Sonnet + medium~high: 버그 수정, 기능 구현, 코드 리뷰
- Opus + high: 아키텍처 설계, 시스템 점검, 복합 분석, 전략 기획
```
→ "버그 수정"과 "기능 구현"이 Sonnet이라고 되어 있지만, 실제로는 Codex가 해야 함.

### 변경안

**## 모델 라우팅 규칙 (엄격 모드)**

**Sonnet (오케스트레이터 판단 용도만)**
- 1-3파일, <50줄의 단순 수정만
- 작업: 파일 조회, 단순 편집, 위임 판단, 결과 검수
- **금지**: 버그 수정, 기능 구현, 리팩토링 (전부 Codex로)
- 예: "README 첫 줄 수정" → Sonnet 직접 / "버그 고쳐줘" → Codex 위임

**Opus (전략/시스템 설계만)**
- 사용: 오케스트레이션 아키텍처, 시스템 점검, 장기 전략
- 사용 빈도: 월 5-10회 정도
- **절대 금지**: 코드 생성, 문서 작성, 일상 판단
- 예: "토큰 절약 시스템 재설계" → Opus / "이 task는 Codex 위임 맞나?" → Sonnet

**Codex (코딩/분석 중심)**
- 4+ 파일, 50+ 줄, 모든 구현/리팩토링
- 코드 리뷰, 에러 분석, 데이터 처리
- 캐싱 효율 80% → 최우선 활용

**Gemini (리서치/문서 분석)**
- 웹 검색 필요한 모든 리서치
- 50+ 페이지 문서 요약/분석
- 배치 작업 (대량 콘텐츠 수집, 크롤링)
- 일 1500 중 현재 200 미만 → 극도로 저활용

---

## 작업 2: AGENTS.md 동일 업데이트

파일: `C:/Users/1/projects/agent-orchestration-Codex_main/AGENTS.md`

"## 1. 기본 규칙 + 모델/Effort 가이드" 섹션을 위와 동일하게 변경.
(adapters/codex_global.md도 동시에 업데이트)

---

## 작업 3: agent_config.yaml 한도 상태 파악 및 주석 추가

파일: `C:/Users/1/projects/agent-orchestration/agent_config.yaml`

### 현재 상태 (2026-03-20 기준)
각 섹션 끝에 아래 주석 추가:

```yaml
limits:
  claude_max_20x:
    window: "5h rolling"
    opus_per_window: 180          # 예상 사용: 월 5-10회 × 100K = 500K-1M
    sonnet_per_window: 900        # 지난 4h: 700K 소모 (과다)
    haiku_per_window: 2700        # 사용 0 (subagent 제거 후)
  chatgpt_pro:
    window: "5h rolling + weekly"
    codex_note: "Codex: 1.8M cached가 recent peak. 캐싱 효율 95%+ 유지."  # 극도로 저활용
  gemini_pro:
    daily_requests: 1500          # 사용: 200/day (13% 미만)
    rpm: 120
    pro_prompts_day: 100
    flash_prompts_day: 300
```

---

## 작업 4: 다음 세션 토큰 절약 체크리스트 작성

파일: `C:/Users/1/projects/agent-orchestration/docs/TOKEN_DISCIPLINE.md` (신규 생성)

```markdown
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
```

---

## Done Criteria
- [ ] CLAUDE.md "모델 라우팅 규칙" 섹션 완전 재작성 (엄격 모드)
- [ ] AGENTS.md 동일 내용 반영
- [ ] adapters/claude_global.md + adapters/codex_global.md 동기화
- [ ] agent_config.yaml 한도/사용 주석 추가
- [ ] TOKEN_DISCIPLINE.md 신규 생성 및 저장
- [ ] 두 레포(agent-orchestration, Codex_main) git commit & push
- [ ] sync.sh 실행으로 모든 기기에 배포 (필요 시)

---

## Constraints
- Plan Mode 관련 항목은 모두 제거 (CLAUDE.md에서)
- Sonnet은 "판단"만, 절대 구현 금지
- Codex 캐싱 효율 유지를 위해 반복 작업은 brief 재사용
