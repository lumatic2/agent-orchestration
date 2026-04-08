# AI Orchestration Roadmap — Big Picture

> agent-orchestration의 다음 진화 방향. 현재 상태, 업그레이드 공간, 선정된 경로.
> 작성: 2026-04-08

## 현재 상태 (2026-04-08 기준)

- **구조**: Claude Code가 유일한 오케스트레이터. Codex/Gemini는 Skill 플러그인(`codex:rescue`, `gemini:rescue`)을 통해 1회성 위임만 받는 워커
- **통신**: 파일 기반 (SHARED_PRINCIPLES.md, adapters/*, ~/AGENTS.md, ~/CLAUDE.md) + Skill CLI 래퍼
- **공통 원칙 통일**: `sync.sh`가 SHARED_PRINCIPLES를 Claude/Codex/Gemini 설정 파일에 정적 주입. 세 기기(Windows/Mac Air/M4) 배포 완료
- **한계**: 1차원 위임만 됨 — Claude가 Codex한테 일 시키고, Codex는 결과만 돌려줌. 에이전트 간 대화, 병렬 작업, 장시간 자율 루프, 적대적 협업 등의 고차 패턴 없음

## 업그레이드 공간 4개 축

| 축 | 현재 | 가능한 업그레이드 |
|---|---|---|
| **통신 패턴** | 1회성 위임 | 다중 턴 대화, 공유 작업 메모리, 에이전트 간 직접 교류 |
| **구조** | 평평 (Claude 단독 조율) | 계층(planner→sub→executor), 병렬, 토론/스왐 |
| **자율성** | 사용자 단계별 트리거 | 장시간 실행, 목표 주도 루프, 자가 교정 |
| **프로토콜** | 파일 + Skill CLI | MCP 기반 에이전트 노출, A2A 프로토콜, 벡터 공유 메모리 |

## 3가지 유망 방향

### 방향 1 — 적대적 리뷰 파이프라인 (Adversarial Review Chain)

**흐름**: Claude 계획 → Codex 구현 → Gemini 적대적 리뷰("이 코드를 깨뜨려봐") → Claude 심판 → 필요 시 Codex 재시도

**장점**:
- 현재 인프라에 거의 손대지 않고 가능. `scripts/review-pipeline.sh` 수준
- 두 모델의 다른 훈련 데이터로 blind spot 보완 (Codex가 놓친 걸 Gemini가 잡고, 역도 성립)
- 즉시 효용 체감. 구현 1-2시간

**단점**:
- 구조적 업그레이드가 아니라 *사용 패턴* 업그레이드. 근본적 스케일업은 아님
- 병렬·계층 패턴으로 확장하기 어려움 (여전히 1차원)

**ROI**: 즉시 유용, 장기 기반은 아님

---

### 방향 2 — Codex/Gemini를 MCP 서버로 노출 ⭐ **선정**

**아이디어**: Codex CLI와 Gemini CLI를 MCP(Model Context Protocol) 서버로 래핑. 기존 `Skill("codex:rescue", ...)`는 Claude Code 전용이지만, MCP 서버는 Cursor, Windsurf, Continue, 심지어 Codex/Gemini 서로서로 어느 MCP 클라이언트에서도 도구로 호출 가능.

**장점**:
- **계층/병렬/토론 패턴의 기반 인프라**가 됨. 한 번 깔면 방향 1도 훨씬 자연스럽게 구현됨 (Claude가 MCP로 Codex를 부르고, Codex가 MCP로 Gemini를 부르는 체인 가능)
- Anthropic MCP 생태계 모멘텀 편승. 점점 더 많은 도구가 MCP로 통합 중
- 에이전트를 "도구"로 취급 가능 — 이건 CrewAI/LangGraph 같은 Python 프레임워크 도입 없이도 멀티 에이전트 조합을 가능하게 함
- 단기적으로는 효용이 작아도 **후속 작업의 승수 효과**가 큼

**단점**:
- MCP 서버 구현 학습 곡선 (Node.js/Python SDK)
- 기존 Skill 플러그인과 중복될 수 있음 — 정리 필요
- 당장의 워크플로에는 큰 변화 없음

**ROI**: 단기 중간, 장기 최대

---

### 방향 3 — 장시간 Deep Research 모드 (Gemini Pro 기반)

**흐름**: 한 줄 리서치 질문 → 다중 라운드 자율 탐색 루프 → 중간 가설 생성 → 추가 검색 쿼리 자가 생성 → 반복 → 최종 보고서. 30분~수 시간

**장점**:
- 시장 트렌드 한복판. OpenAI Deep Research, Perplexity Deep Research 등이 유료 서비스로 경쟁 중. 로컬 자작은 차별화
- 기존 인프라에 "continuation loop"만 추가하면 됨
- vault 저장과 결합 시 지식 베이스 자동 증강 가능

**단점**:
- 비용 통제 필요 (Gemini Pro 장시간 호출). 중단/재개 로직 복잡
- Gemini CLI의 웹 검색 도구 안정성·속도에 의존
- 방향 2 없이 만들면 다른 에이전트(Codex 등)와 연계가 어려움

**ROI**: 특정 유스케이스에 한해 매우 높음

---

## 선정 결과: 방향 2

**근거**:
- 방향 1과 3은 방향 2 위에 올리면 자연스럽게 구현됨 (MCP로 Codex가 노출되면 리뷰 체인도, Deep Research 중 Codex 호출도 쉬워짐)
- 장기 기반 투자. 지금 깔아두면 반년 안에 여러 후속 작업의 공통 인프라가 됨
- Anthropic MCP 생태계 모멘텀 편승 — 표준화된 방향

**실행 순서 (예상)**:
1. MCP 서버 오픈소스 예시 조사 (Python/Node.js SDK, CLI 래퍼 패턴)
2. `codex-mcp` 서버 프로토타입 (Codex CLI 호출 → MCP 도구로 노출)
3. `gemini-mcp` 서버 프로토타입
4. `~/.claude/settings.json`의 MCP 서버 목록에 등록
5. 기존 Skill 플러그인과의 관계 정리 (유지 vs 제거 vs 공존)
6. 다른 MCP 클라이언트(Cursor 등)에서 호출 검증

**후속으로 풀릴 일들**:
- 방향 1 (적대적 리뷰): Claude가 Codex MCP 호출 → Codex 결과를 Gemini MCP에 넘겨 리뷰 요청 — 별도 스크립트 없이 Claude의 tool calling으로 자연 체이닝
- 방향 3 (Deep Research): Gemini MCP를 받아 Claude가 "continuation loop"를 직접 돌리거나, 별도 Deep Research 에이전트가 Gemini MCP + 웹 MCP를 조합해서 사용

## 의도적으로 배제한 경로

- **LangGraph / CrewAI / AutoGen**: Python 프레임워크 기반. 현재 Bash + CLI + MCP 구조와 임피던스 미스매치. 도입 시 기존 sync.sh/Skill 인프라를 거의 버려야 함
- **OpenAI Swarm**: OpenAI 중심. Claude Code 생태계와 맞물리기 어려움
- **Devin-style 완전 자율**: 구현 노력 대비 ROI 낮음 (Codex가 이미 부분적으로 수행)

## 참고 자료 수집 필요

- MCP Python SDK (`mcp` 패키지) 또는 TypeScript SDK 공식 문서
- 기존 CLI 래핑 MCP 서버 예시 (예: `mcp-server-git`, `mcp-server-fetch`)
- Codex CLI의 비대화형 인터페이스 사양 (이미 codex-companion.mjs가 있음 — 참고)
- Gemini CLI의 비대화형 인터페이스 사양
- Anthropic MCP 공식 레지스트리에서 "agent-as-tool" 사례

→ 다음 세션에서 타겟 리서치 + 프로토타입 시작
