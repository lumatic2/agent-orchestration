# Task: AGENTS.md 재작성 (누락 항목 보완)

## Goal
`~/projects/agent-orchestration-Codex_main/AGENTS.md`를 재작성한다.
이번에는 아래 파일들을 정확히 읽고 통합한다.

## 읽어야 할 원본 파일 (정확한 경로)
1. `C:/Users/1/CLAUDE.md` — 글로벌 Claude instruction (실제 원본)
2. `C:/Users/1/projects/agent-orchestration/ROUTING_TABLE.md` — 전체 라우팅 테이블

## 기존 AGENTS.md 확인
현재 `C:/Users/1/projects/agent-orchestration-Codex_main/AGENTS.md`를 먼저 읽고,
아래 누락 항목들을 보완하여 완전한 버전으로 덮어쓴다.

## 누락되어 추가해야 할 항목

### CLAUDE.md에서 누락된 것
1. **Handoff 섹션** — CLI/API 없는 도구(Figma, Midjourney, Gamma, Suno, Kling)에 대한
   handoff document 생성 규칙. 언제 생성하는지, 어떻게 생성하는지, 사용 가능한 템플릿 목록
   (단, "Skill Override Guard"의 Skill tool 관련 내용은 제거)

2. **Reference Files** — 주요 파일 위치 목록
   (경로는 agent-orchestration-Codex_main 기준으로 업데이트)

### ROUTING_TABLE.md에서 누락된 것
3. **Codex 모델 선택 가이드** — Heavy/Default/Light/spark 기준 표
4. **Codex 운영 룰** — 3가지 규칙 (태스크 분할 우선, 탐색→수정→테스트, No-touch 명시)
5. **Gemini 운영 룰** — 4가지 규칙 (bullet 형식, Tactical Map 모드, Pro vs Flash 기준표, Tactical Map 우선)
6. **Interactive Workflow** — 브레인스토밍/레퍼런스 리서치 패턴 (수집→판단→심화→결정→구현 루프)
7. **Large Document Handling** — 50+ 페이지 문서는 Gemini에 위임 후 요약본만 처리
8. **Task Coverage Map** — 자동화 가능한 작업 범위 전체 표

## 마이그레이션 규칙 (기존과 동일)
- Claude Code 전용 항목 제거: Plan Mode, EnterPlanMode/ExitPlanMode, subagent types(Explore/Plan), Skill tool
- "Claude Code" → "Codex" (오케스트레이터 주체)
- orchestrate.sh 경로: `~/projects/agent-orchestration-Codex_main/scripts/orchestrate.sh`
- Queue 경로: `~/projects/agent-orchestration-Codex_main/queue/`
- Token Discipline에서 Haiku/Sonnet subagent 항목 제거, Codex 워커 중심으로 재작성
- Domain-specific routing: "Claude(MCP 보유)" → "Codex(MCP 직접)"

## 최종 AGENTS.md 구조 (순서 유지)
1. 기본 규칙 + 모델/Effort 가이드
2. FIRST ACTION (Every Session)
3. Pre-flight
4. Self-Execution Guard
5. Multi-Agent Orchestration (Decision Flow + Research-First Rule)
6. Handoff (누락 항목 추가)
7. orchestrate.sh 사용법
8. Domain-Specific Routing
9. Codex 모델 선택 가이드 (누락 항목 추가)
10. Codex 운영 룰 (누락 항목 추가)
11. Gemini 운영 룰 (누락 항목 추가)
12. Interactive Workflow (누락 항목 추가)
13. Large Document Handling (누락 항목 추가)
14. Queue-First Workflow
15. Task Coverage Map (누락 항목 추가)
16. Reference Files (누락 항목 추가)
17. Knowledge Vault
18. Session End

## Done Criteria
- [ ] `C:/Users/1/CLAUDE.md` 읽기 완료
- [ ] `C:/Users/1/projects/agent-orchestration/ROUTING_TABLE.md` 읽기 완료
- [ ] 누락 항목 8개 모두 포함
- [ ] Claude Code 전용 문법 없음
- [ ] `C:/Users/1/projects/agent-orchestration-Codex_main/AGENTS.md` 덮어쓰기 완료
- [ ] git commit & push 완료
