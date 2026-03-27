# /orchestrate — 오케스트레이션 규칙 참조

멀티에이전트 라우팅 규칙 전체를 로드한다. CLAUDE.md 요약본의 상세 버전.

---

## Self-Execution Guard (엄격 적용)

| 조건 | 액션 |
|---|---|
| 4+ 파일 수정 | STOP → `orchestrate.sh codex "task" name` |
| 50+ 줄 코드 작성 | STOP → `orchestrate.sh codex "task" name` |
| 100+ 줄 문서 분석 | STOP → `orchestrate.sh gemini "task" name` |
| 리서치 필요 | STOP → `orchestrate.sh gemini "task" name` |
| 1-3파일 <50줄 단순 편집 | 직접 수행 |

## 에이전트 선택 기준

| 작업 유형 | 에이전트 |
|---|---|
| 웹 검색 / 트렌드 조사 | Gemini Flash |
| 50+ 페이지 문서 분석 | Gemini Pro |
| 코드 구현 4+ 파일 | Codex |
| 빠른 편집 1-2 파일 | Codex Spark |
| Google 생태계 (YouTube, Drive) | Gemini |
| 외부 서비스 MCP 연동 | Claude 직접 |

## 위임 커맨드

```bash
# 리서치
bash ~/projects/agent-orchestration/scripts/orchestrate.sh gemini "task" task-name
bash ~/projects/agent-orchestration/scripts/orchestrate.sh gemini-pro "deep" task-name

# 코딩
bash ~/projects/agent-orchestration/scripts/orchestrate.sh codex "task" task-name
bash ~/projects/agent-orchestration/scripts/orchestrate.sh codex-spark "quick" task-name

# 큐 관리
bash ~/projects/agent-orchestration/scripts/orchestrate.sh --status
bash ~/projects/agent-orchestration/scripts/orchestrate.sh --resume
bash ~/projects/agent-orchestration/scripts/orchestrate.sh --complete T001 "summary"
```

## Pre-flight 체크 (비자명한 작업 시)

빠진 정보 있으면 묻기:
- 신규 프로젝트: 플랫폼 / 핵심 기능 3개 / 참고 레퍼런스 / 기술 스택
- 리팩토링: 변경 범위 / 제약 조건 / 완료 기준
- 리서치: 원하는 출력 형식 / 깊이

## Research-First 규칙

웹 검색이 필요한 모든 것 → Gemini 먼저. 예외 없음.
"이미 알고 있어도" 위임. Gemini는 1M 컨텍스트 + 1,500 req/day.

## Domain Routing

```
Google/YouTube/Drive  → Gemini + Claude(정리)
이미지/영상/오디오    → Gemini + Codex(구현)
데이터 파이프라인     → Codex(대규모) / Claude(소규모)
Notion/Slack MCP      → Claude 직접
CI/CD DevOps          → Codex + Gemini(에러분석)
```

## Claude Code Sub-agents (신규)

```
/agents gemini-researcher  → Gemini 리서치 위임
/agents codex-coder        → Codex 구현 위임
```

## 참조 파일

- 전체 라우팅: `~/projects/agent-orchestration/ROUTING_TABLE.md`
- 공유 메모리: `~/projects/agent-orchestration/SHARED_MEMORY.md`
- 설정: `~/projects/agent-orchestration/agent_config.yaml`
