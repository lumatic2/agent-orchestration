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

1. 단순 리서치인가? (≤3회 검색, 단일 주제, 사실 조회) → Claude 직접 처리
2. 복잡 리서치인가? (4+ 소스, 트렌드, 비교 분석, 대량 수집) → Gemini 선행
3. 브라우저/GUI/시각화 작업인가? → **OpenClaw** (아래 참조)
4. 1-3파일, 5분 내 작업인가? → Claude 직접 처리
5. 대규모 코드 작업(5+ 파일, 테스트 루프)인가? → Codex 단독
6. 리서치+구현 결합인가?
   - 소규모 구현: Claude + Gemini
   - 대규모 구현: Claude + Codex
   - 심층 리서치+대규모 구현: Full orchestration

원칙:
- 단순 리서치(≤3회 검색, 단일 주제)는 Claude가 직접 처리한다.
- 복잡 리서치(4+ 소스, 트렌드/비교 분석, 대량 수집, 50p+ 문서)는 Gemini에 위임한다.
- 수치 임계값, 모델 tier, fallback 순서는 `agent_config.yaml`을 따른다.

---

## Decision Matrix

| 작업 특성 | 라우팅 |
|---|---|
| 단순 수정 (1-3 파일) | Claude alone |
| 단순 리서치 (≤3 검색, 단일 주제) | Claude alone |
| 복잡 리서치/문서 분석 (4+ 소스) | Gemini alone |
| 대규모 구현/리팩터 | Codex alone |
| 리서치 후 소규모 반영 | Claude + Gemini |
| 분석 후 대규모 구현 | Claude + Codex |
| 리서치+대규모 구현 동시 | Full orchestration |
| JS SPA 스크레이핑 | **OpenClaw** |
| 웹 폼 인터랙션 (클릭/입력) | **OpenClaw** |
| canvas 차트/시각화 렌더링 | **OpenClaw** |
| 로그인 세션 필요한 웹 작업 | **OpenClaw** |
| 브라우저 스크린샷 | **OpenClaw** |

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
| 웹 브라우저 자동화 | **OpenClaw** | JS SPA, 폼 인터랙션, 세션 유지 |
| 데이터 시각화 (차트/그래프) | **OpenClaw** | canvas.eval → PNG → Telegram |
| 실시간 웹 시세/데이터 | **OpenClaw** | JS 렌더링 필요 사이트 |

### OpenClaw 라우팅 트리거 키워드
- "브라우저로 열어", "사이트에서 가져와", "클릭해서", "검색해서 결과"
- "차트 그려줘", "시각화해줘", "그래프로 보여줘"
- "JS 렌더링", "SPA", "로그인하고"
- "스크린샷 찍어"

### OpenClaw 제약 (2026-03-23 기준)
- screen.record: macOS 26 (Tahoe beta) 미지원 → screencapture 폴백
- system.run: 헤드리스 환경에서 approval UI 없어 제한적
- Mac mini M4에만 설치 → Windows/MacAir는 SSH 자동 위임

---

## 운영 원칙

- 중복 라우팅 규칙은 본 문서에 추가하지 않는다.
- 모델명/한도/fallback 수정은 `agent_config.yaml`에서만 수행한다.
- 본 문서는 의사결정 플로우와 책임 분리만 유지한다.