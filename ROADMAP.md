# agent-orchestration ROADMAP

## proj 런처 공개 준비

### 독립 레포 분리
- [x] `proj` 관련 코드만 추출 (proj.zsh, powershell_profile.ps1의 proj 함수)
- [x] 원클릭 설치 스크립트 작성 (setup.sh / setup.ps1)
- [x] README 작성: 기능 설명, 스크린샷/GIF, 설치 방법
- [x] GitHub 레포 생성 및 푸시

### 블로그 글
- [ ] "비개발자가 Claude Code로 20개 프로젝트를 관리하며 만든 런처" 초안
- [ ] 스크린샷 캡처 (proj 메뉴, status, archive, agent 선택 등)
- [ ] 브런치 또는 포트폴리오 블로그에 발행
- [ ] GitHub 레포 링크 연결

## proj 기능 개선
- [x] Windows(PowerShell) / Mac(zsh) 코드 통일
- [x] fzf 기반 메뉴 + 단축키 (ctrl+N/E/R/D)
- [x] 관리 액션 후 메뉴 복귀 (while 루프)
- [x] pin/archive 필드 (ctrl+P, ctrl+X, ctrl+A)
- [x] Esc 단계별 뒤로가기 (agent→worktree→project)
- [x] ctrl+S status 화면 (git/branch/worktree/ROADMAP)
- [x] Windows Terminal proj 프로필 추가
- [x] fzf 후 claude stdin 격리 (Start-Process)
- [ ] Mac에서 테스트 및 호환성 확인

---

## 오케스트레이션 재설계 v2

> 배경: 기존 글로벌 CLAUDE.md의 "상황별 자동 제안" 규칙이 실제로 작동하지 않음(Claude가 알아서 제안을 거의 안 함). Codex/Gemini 활용도 저조. 진입점을 **사용자 호출 스킬**(`/codex`, `/gemini`)로 명시화하여 해결.

### 설계 원칙
- **철학**: Verification-First 유지. Claude가 주 실행자, 위임은 교차검증/협업 목적
- **진입점**: 사용자가 `/codex` 또는 `/gemini` 호출 → Claude가 맥락(git + 최근 대화) 기반으로 추천 메뉴 제시 → 사용자 선택 → 백그라운드 실행
- **AskUserQuestion 미사용**: enum 고정 → 활용처 제한. 자연어로 추천·응답
- **인프라 재활용**: plugin의 `codex-rescue`·`gemini-rescue` subagent와 `*-companion.mjs` 그대로 사용. 재발명 금지
- **협업 모드 내장**: triangulate / debate / cross-review 패턴으로 mesh 근사 (진짜 peer-to-peer는 기술적 불가, Claude 중재로 근사)

### v2.0 (완료, iteration 1)
- [x] `/codex`, `/gemini` 스킬 초안 작성 및 배포 (`~/projects/custom-skills/{codex,gemini}/`)
- [x] 기본 모델 지정: Codex=`gpt-5.4`, Gemini=`gemini-2.5-pro` (preview alias 금지)
- [x] Codex `adversarial-review` 자가 검증 실행 → 5개 high 심각도 지적 수신
- [x] Gemini triangulate 시도 실패 — mesh "collaboration theater" 위험 실증됨

### v2.1 (Codex 비평 반영, 완료)
- [x] `scripts/codex-dispatch.sh`, `scripts/gemini-dispatch.sh` wrapper 추가
  - Plugin cache internals 의존 제거 (Codex #4)
  - Plugin 업그레이드·경로 변경 시 wrapper만 수정
  - healthcheck 커맨드 포함 (companion + CLI 동작 확인)
- [x] Mesh 협업 모드(triangulate/debate/cross-review) 제거 (Codex #5 + Gemini 실증)
  - orchestration 계약(correlation/join/timeout/partial-failure) 정의 전까지 비활성
- [x] 스킬 맥락 수집 범위 확장 (Codex #2)
  - git status만 → 전체 대화 흐름 + diff stat + tool 출력 + 의도 포함
- [x] 실행 전 echo-confirm 규칙 추가 (Codex #3)
  - rescue(side-effect 가능)는 1줄 확인 후 실행
  - review/adversarial(read-only)은 즉시 실행

### v2.2 (완료)
- [x] Passive surfacing (Codex #1 부분 반영)
  - 고위험 맥락(migration/auth/crypto/security 파일 변경)에서 "/codex 교차검증 가능" 한 줄 정보 제공
- [x] `adapters/claude_global.md` 슬림화
  - 위임 매트릭스·Examples 삭제 → "/codex, /gemini 스킬 경유" 단일 안내
- [x] `adapters/claude.md`, `ROUTING_TABLE.md`의 Heavy-Delegation 잔재 제거
- [x] `bash scripts/sync.sh`로 ~/CLAUDE.md, ~/.codex/, ~/.gemini/ 재배포 (line budget 모두 통과)
- [ ] 불필요 plugin 스킬 `/skill-toggle` 정리 (`codex:codex-cli-runtime`, `codex:gpt-5-4-prompting`, `codex:codex-result-handling`) — 사용자 대화형 실행 필요

### v3 검토 대상 (미래)
- [ ] Mesh 협업 복원 — 계약 정의 후
  - per-leg correlation ID
  - join barrier + timeout
  - partial-failure 명시 보고 ("PARTIAL: X leg missing")
  - stale job ID 거부

### 검증 기준 (v2.1)
- `/codex`, `/gemini` 호출 시 현재 대화 흐름·git 상태 반영한 맥락 추천 3-5개 제시
- rescue 모드는 echo-confirm 후 실행
- Plugin 경로 직접 참조 없음 (wrapper 경유)
- 토큰 비용: Claude는 오케스트레이션만, 무거운 추론은 Codex/Gemini CLI 측

### 알려진 한계 및 의도된 트레이드오프
- 사용자가 "타이밍 잡아 호출"해야 함 — Verification-First 원칙상 의도적 포기
- Gemini가 복잡 멀티파트 프롬프트에 약함 — 단일 명확 질문으로 좁혀 보내야 함 (스킬에 문서화)

---

## K-IFRS 개인용 RAG/MCP 시스템

> 배경: K-IFRS 기준서를 프로그램적으로 조회할 공식 API/MCP가 부재. 빅4 사내 AI는 외부 비공개. 외부 공개는 KASB·IFRS Foundation 저작권 장벽으로 진입 불가. **저작권법 제30조 사적이용 복제·제35조의5 공정이용** 범위 안에서 본인 학습·실무·포트폴리오 시연용으로 비공개 운영.

### 포지셔닝
- 본인 PC 로컬에서만 동작. 외부 공개·배포·공유 없음
- 코드는 GitHub private. 공개 가능 산출물(아키텍처 글, 데모 영상, 평가 리포트)로 포트폴리오 효과 흡수
- `tax-agent` 레포 패턴(파싱·인덱싱·MCP 래퍼) 재사용 → 신규 개발 비용 최소화
- 외부 공개·협업은 **별도 후속 프로젝트**로 분리 (KASB·KICPA 컨택은 그때)

### 성공기준 (4축 — 정량)

| 축 | 기준 |
|---|---|
| **A. 실사용** | 본인이 회계 과목 공부·과제에서 **주 3회 이상 자발적 사용** (4주 연속) |
| **B. 품질 우위** | 평가셋 50문항에 대해 본인 시스템 vs. naive PDF(NotebookLM/Claude Projects) 정확도 **20%p 이상 우위** (조항 인용 정확성 + 할루시네이션 빈도) |
| **C. 커버리지** | 수업·실무 빈출 Top 5 기준서 완전 인덱싱: **1115 수익, 1116 리스, 1109 금융상품, 1001 재무제표 표시, 1019 종업원급여** |
| **D. 포트폴리오 산출물** | 공개 가능 3종 완성: ① 아키텍처 블로그 글 ② 데모 영상 3-5분 ③ 평가 메트릭 리포트 |

### Phase 분해

#### Phase 1 — PoC (단일 기준서)

목표: 기준서 1개로 파이프라인 전체(파싱→저장→MCP 조회) 검증

- [ ] 사전 작업: `tax-agent` 레포 코드 리뷰, 재사용 가능 모듈 식별 (파싱·MCP·평가 하네스)
- [ ] **K-IFRS 1115호 (수익)** PDF KASB 사이트에서 다운로드
- [ ] PDF → 조·항·호 계층 JSON 파싱 (`pypdf` + 조항 정규식, tax-agent 파서 포팅)
- [ ] SQLite 스키마 설계: `standard / article / paragraph / clause / cross_reference / amendment`
- [ ] FastMCP 기반 MCP 서버 — tools: `get_article`, `search_lexical`
- [ ] Claude Code에 등록 → 본인 질문 5개로 동작 확인
- [ ] **B축 마이크로 검증**: 같은 5개 질문을 NotebookLM에도 던져 정확도 비교
- **Phase 1 종료 조건**: B축 5건 비교에서 본인 시스템 우위 ≥ 3건

#### Phase 2 — Top 5 커버리지 + 하이브리드 검색 + 크로스레퍼런스

목표: C축 달성 + B축 본격 평가

- [ ] 나머지 4개 기준서(1116, 1109, 1001, 1019) PDF 확보 + 파싱
- [ ] 임베딩 인덱스 추가 (sentence-transformers 한국어 모델 또는 OpenAI text-embedding-3-small)
- [ ] 하이브리드 검색 구현: 키워드(SQLite FTS5) + 시맨틱(임베딩) 점수 결합
- [ ] **크로스레퍼런스 그래프**: 조항 본문에서 "제X조" 패턴 추출 → `cross_reference` 테이블 채움
- [ ] MCP tools 확장: `search_hybrid`, `get_referenced_articles`, `get_referencing_articles`
- [ ] **B축 평가셋 50문항 작성**: 본인이 회계 수업·실무에서 실제 부딪힌 질문 + 기준서별 골드 답안(인용 조항 번호) 라벨링
- [ ] 평가 하네스 작성: 본인 시스템 vs naive PDF 자동 비교 스크립트
- **Phase 2 종료 조건**: C축 완료(Top 5 인덱싱) + B축 평가에서 우위 20%p 이상

#### Phase 3 — 실사용 안정화 + 포트폴리오 패키지

목표: A축 + D축 달성

- [ ] **개정이력**: 각 조항의 개정일·이전 버전 추적 (`amendment` 테이블 채움)
- [ ] **해설 레이어**: 본인 작성 요약·해설 별도 테이블에 추가 (저작권 안전한 창작물)
- [ ] MCP tools 확장: `get_amendment_history`, `get_user_note`, `add_user_note`
- [ ] Claude Desktop에도 등록 → 모바일·데스크톱 워크플로 통합
- [ ] **A축 측정**: 4주 사용 로그(쿼리 일시·내용) 기록 → 주 3회 기준 검증
- [ ] **D축 산출물 ①** 아키텍처 블로그 글 (브런치 또는 포트폴리오 사이트)
- [ ] **D축 산출물 ②** 데모 영상 3-5분 (실제 사용 시연)
- [ ] **D축 산출물 ③** 평가 메트릭 리포트 (Phase 2 평가 결과 + 방법론)
- **Phase 3 종료 조건**: A·B·C·D 4축 모두 통과

### 작업 원칙

- **기준서 PDF·텍스트·임베딩·DB 덤프는 절대 git commit 금지** (`.gitignore` 최상단에 `data/`, `*.db`, `*.pdf`, `embeddings/`)
- 코드 레포는 **GitHub private** 유지
- 동료·친구 공유 ❌ — 사적이용 범위 깨짐
- 향후 외부 공개·협업 의사 굳어지면 별도 프로젝트로 분리하여 KASB·KICPA 컨택

### 향후 분기점 (이 프로젝트 외)

- 외부 공개 버전: 별도 레포 `kifrs-public` — KASB 라이선스 확보 후 메타데이터+해설 한정
- KICPA 협업 가능성: GIST Doyoon Song 케이스(KICPA 공식 챗봇) 참고하여 회원용 도구 제안

### 메모

- KASB 메일 v3.4 초안은 보류. 외부 공개 단계 진입 시 재활용
- GIST 학부논문(Doyoon Song, 2025) 분석: KICPA 공식 협업 사례. 외부 개인 직접 진입 선례는 여전히 0건 — 공백 자체가 향후 협업 카드
