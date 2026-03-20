# Routing Table

> 오케스트레이션 판단 기준. 수치 한도/모델명은 `agent_config.yaml`을 단일 진실 소스로 참조한다.

---

## Step -1: Queue First

```bash
bash ~/projects/agent-orchestration/scripts/orchestrate.sh --boot
```

우선순위:
1. Stale dispatched → `--resume`
2. Queued(rate-limited) → `--resume`
3. Pending → dispatch
4. New tasks → 큐 정리 후 수락

---

## Step 0: Do I Need Orchestration?

1. 리서치가 필요한가? → Gemini 선행
2. 1-3파일, 5분 내 작업인가? → Claude 직접 처리
3. 순수 리서치인가? → Gemini 단독
4. 대규모 코드 작업(5+ 파일, 테스트 루프)인가? → Codex 단독
5. 리서치+구현 결합인가?
   - 소규모 구현: Claude + Gemini
   - 대규모 구현: Claude + Codex
   - 심층 리서치+대규모 구현: Full orchestration

원칙:
- 리서치는 Claude가 직접 수행하지 않는다.
- 수치 임계값, 모델 tier, fallback 순서는 `agent_config.yaml`을 따른다.

---

## Decision Matrix

| 작업 특성 | 라우팅 |
|---|---|
| 단순 수정 (1-3 파일) | Claude alone |
| 순수 리서치/문서 분석 | Gemini alone |
| 대규모 구현/리팩터 | Codex alone |
| 리서치 후 소규모 반영 | Claude + Gemini |
| 분석 후 대규모 구현 | Claude + Codex |
| 리서치+대규모 구현 동시 | Full orchestration |

---

## Domain Routing (요약)

| 도메인 | 주 에이전트 | 비고 |
|---|---|---|
| Google 생태계 콘텐츠 분석 | Gemini | 대규모 문서/검색 |
| Google Workspace 직접 조작 | Claude(MCP) | Gmail/Calendar/Sheets/Drive |
| 데이터 파이프라인 | Claude(소규모)/Codex(대규모) | 필요 시 Gemini 분석 |
| Notion 조사+초안 | Gemini | 빠른 원스톱 |
| Notion DB/복잡 편집 | Claude(MCP) | 판단 중심 |
| CI/CD, DevOps | Codex | 에러 원인 분석은 Gemini |

---

## 운영 원칙

- 중복 라우팅 규칙은 본 문서에 추가하지 않는다.
- 모델명/한도/fallback 수정은 `agent_config.yaml`에서만 수행한다.
- 본 문서는 의사결정 플로우와 책임 분리만 유지한다.