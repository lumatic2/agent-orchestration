# Routing Table

> Verification-First 원칙. Claude 직접 실행 기본값, Codex/Gemini 위임은 **사용자 호출 스킬**(`/codex`, `/gemini`) 경유.
> 수치 한도/모델명은 `agent_config.yaml` 참조.

---

## Step 0: 어디서 처리할까?

1. 코드 편집·리서치·분석 → **Claude 직접**
2. 브라우저/GUI/JS 렌더링/세션 → **OpenClaw** (아래)
3. 교차검증이 필요한가? → 사용자가 `/codex` 또는 `/gemini` 호출
4. Claude는 자동 위임하지 않음 — 필요 시 답 끝에 한 줄 정보만 제공

---

## Decision Matrix

| 작업 특성 | 라우팅 |
|---|---|
| 코드 편집, 리서치, 분석, 계획 | Claude 직접 |
| 교차검증(리뷰·adversarial·fact-check·rescue) | 사용자 `/codex` 또는 `/gemini` 호출 |
| JS SPA 스크레이핑 | **OpenClaw** |
| 웹 폼 인터랙션 (클릭/입력) | **OpenClaw** |
| canvas 차트/시각화 렌더링 | **OpenClaw** |
| 로그인 세션 필요한 웹 작업 | **OpenClaw** |
| 브라우저 스크린샷 | **OpenClaw** |

---

## Domain Routing (요약)

| 도메인 | 처리 |
|---|---|
| Google Workspace 직접 조작 | Claude(MCP) |
| Notion DB/복잡 편집 | Claude(MCP) |
| 데이터 파이프라인, CI/CD | Claude 직접 — 필요 시 `/codex:review` 제안 |
| 고위험 파일(auth/crypto/migration/security) 변경 | Claude 작성 후 "`/codex` 교차검증 가능" 정보 제공 |
| 웹 브라우저 자동화 | **OpenClaw** | 
| 데이터 시각화 (차트/그래프) | **OpenClaw** |
| 실시간 웹 시세/데이터 | **OpenClaw** |

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
- Claude 자동 위임 금지. 위임은 사용자가 `/codex`, `/gemini` 호출로만 개시.