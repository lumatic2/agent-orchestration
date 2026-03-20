## Goal
Obsidian vault에 AI 회사 템플릿 + 회계법인 인스턴스 파일 총 13개를 구현한다.
Vault 루트: /Users/luma2/vault/
접근 방법: ssh luma2@m1 후 파일 작성

---

## Phase 1 — 템플릿 인프라 (30-projects/my-company/ 폴더 업데이트)

### 파일 1: 30-projects/my-company/domain.yaml (신규)

```yaml
# AI Company OS — Domain Config
# 이 파일만 교체하면 업종이 전환된다.

domain:
  name: 콘텐츠 회사
  industry: content
  reference: "luma (현재 운영 중)"
  language: ko

agents:
  - role: CEO
    persona: "전략가 — 의사결정·방향 설정"
    tools: [claude-code, notion, telegram]
  - role: CMO
    persona: "콘텐츠 디렉터 — 채널 전략·콘텐츠 캘린더"
    tools: [gemini, brunch, youtube]
  - role: CTO
    persona: "자동화 엔지니어 — 파이프라인·배포"
    tools: [codex, github, mac-mini-m1]
  - role: CFO
    persona: "재무 분석가 — 수익·비용 추적"
    tools: [notion, spreadsheet]
  - role: BD
    persona: "비즈니스 개발 — 파트너십·딜"
    tools: [claude-code, notion]

workflows:
  - id: 01-content-cycle
    name: 콘텐츠 생산 사이클
    trigger: "cron(daily 08:00)"
    sop_file: sop/01-content-cycle.md
  - id: 02-sales-cycle
    name: 세일즈/파트너십 사이클
    trigger: "event(lead_received)"
    sop_file: sop/02-sales-cycle.md
  - id: 03-dev-cycle
    name: 개발·자동화 사이클
    trigger: "event(feature_requested)"
    sop_file: sop/03-dev-cycle.md
  - id: 04-finance-cycle
    name: 재무 결산 사이클
    trigger: "cron(monthly last-day)"
    sop_file: sop/04-finance-cycle.md
  - id: 05-monitoring
    name: 시스템 모니터링
    trigger: "cron(daily 09:00)"
    sop_file: sop/05-monitoring.md

tools:
  - name: Gemini
    type: api
    purpose: 리서치·초안 생성
  - name: Claude Code
    type: cli
    purpose: 오케스트레이션·코드 생성
  - name: Codex
    type: api
    purpose: 코드 구현·자동화
  - name: Notion
    type: saas
    purpose: 운영 허브·프로젝트 관리
  - name: GitHub
    type: saas
    purpose: 코드 버전 관리
  - name: "Mac mini M1"
    type: server
    purpose: cron 실행 서버

escalation:
  - condition: 자동화 파이프라인 오류 3회 이상
    action: "telegram_alert → CEO 개입"
  - condition: 콘텐츠 사실 오류 감지
    action: "pause → 수동 검토"
  - condition: 외부 API 비용 임계치 초과
    action: "notify → CFO 승인 요청"
```

---

### 파일 2: 30-projects/my-company/template-guide.md (신규)
frontmatter:
```yaml
---
type: project
domain: strategy
source: claude
date: 2026-03-20
status: active
---
```

내용: 새 업종으로 세팅하는 7단계 가이드 (약 120줄)
- 각 단계마다: 무엇을 해야 하는지 + SOP 정의 방법 + 구체적 예시
- domain.yaml 교체 방법 (inherit 패턴: base 참조 후 오버라이드)
- MetaGPT SOP 형식: 입력→처리→출력→다음 에이전트
- CrewAI 패턴: 에이전트 = 역할 + 목표 + 도구 (도구만 교체하면 도메인 전환)
- AOS 패턴: 스케줄러·컨텍스트·도구 관리 레이어 분리
- 7단계: (1)워크플로우 정의 (2)에이전트-역할 매핑 (3)전문가 AI 페르소나 설정 (4)도메인 도구 선택 (5)트리거 설정 (6)에스컬레이션 기준 (7)파일럿 1개 워크플로우 구현

---

### 파일 3: 30-projects/my-company/sop/01-content-cycle.md
frontmatter: type=project, domain=strategy, source=claude, date=2026-03-20, status=active

SOP 형식:
```
# SOP-01: 콘텐츠 생산 사이클
트리거: cron(daily 08:00) 또는 수동 시작
담당: CMO → CTO → CEO(검수)

단계 1: 트렌드 감지
- 입력: 전날 트렌드 데이터 (Gemini 검색)
- 처리: Gemini가 업계 키워드·이슈 스캔
- 출력: 주제 후보 3-5개
- 다음: 단계 2

단계 2: 주제 선정
- 입력: 주제 후보 리스트
- 처리: CMO 에이전트가 채널 전략 기준으로 평가
- 출력: 오늘의 주제 1개 확정
- 다음: 단계 3

단계 3: 초안 생성
- 입력: 확정된 주제 + 콘텐츠 가이드라인
- 처리: Gemini Flash로 초안 작성
- 출력: 초안 텍스트 (1,500-2,000자)
- 다음: 단계 4

단계 4: 재작성·편집
- 입력: Gemini 초안
- 처리: Claude Sonnet으로 브랜드 톤 맞춰 재작성
- 출력: 최종 원고
- 다음: 단계 5

단계 5: 발행
- 입력: 최종 원고 + 채널 설정
- 처리: 브런치스토리/유튜브 자동 업로드 또는 초안 저장
- 출력: 발행 URL + 타임스탬프
- 다음: 단계 6

단계 6: 성과 측정
- 입력: 발행 URL
- 처리: 24시간 후 조회수·반응 수집
- 출력: 성과 리포트 → Notion 기록
- 다음: 종료

에스컬레이션:
- 사실 오류 의심 → CEO 수동 검토
- 저작권 이슈 감지 → 즉시 중단

완료 기준: 발행 완료 + 성과 데이터 Notion 기록
```

---

### 파일 4: 30-projects/my-company/sop/02-sales-cycle.md
SOP 형식으로:
트리거: event(lead_received)
담당: BD → CEO

단계: 리드 접수 → 자격 검증(예산·의사결정권·니즈·타임라인) → 제안서 작성 → 협상 → 계약 → 온보딩 → 리텐션 관리
에스컬레이션: 계약 금액 1,000만원 초과 → CEO 직접 관여

---

### 파일 5: 30-projects/my-company/sop/03-dev-cycle.md
SOP 형식으로:
트리거: event(feature_requested)
담당: CTO → Codex

단계: 기능 요청 접수 → 스펙 정의 → 구현(Codex) → 테스트 → 코드 리뷰 → 배포 → 모니터링
에스컬레이션: 배포 실패 → CTO 수동 개입 / 보안 이슈 → CEO 즉시 보고

---

### 파일 6: 30-projects/my-company/sop/04-finance-cycle.md
SOP 형식으로:
트리거: cron(monthly last-day)
담당: CFO

단계: 수입·지출 데이터 수집 → 분류·정리 → P&L 작성 → 전월 대비 분석 → 월간 리포트 → CEO 보고
에스컬레이션: 비용 전월 대비 30% 초과 → CEO 즉시 보고

---

### 파일 7: 30-projects/my-company/sop/05-monitoring.md
SOP 형식으로:
트리거: cron(daily 09:00)
담당: CTO

체크리스트: (1)파이프라인 실행 상태 (2)API 오류율 (3)비용 임계치 (4)Notion 동기화 (5)백업 상태
에스컬레이션: 임계치 초과 → Telegram 알림 → CTO 대응

---

### 파일 8: 30-projects/my-company/biz-model.md (기존 파일 업데이트)
기존 내용 유지하고 파일 끝에 아래 섹션 추가:

```markdown
---

## SOP-as-Template 개념

각 워크플로우는 교체 가능한 SOP 단위로 인코딩된다.
`sop/` 폴더의 각 파일 = 입력·처리·출력·에스컬레이션이 명시된 실행 가능한 절차서.

업종 전환 시: `domain.yaml`만 교체 → 새 SOP 작성 → 기존 에이전트 구조 재사용.

외부 패턴 적용:
- **MetaGPT**: 워크플로우를 입력→처리→출력→다음 에이전트 형식의 SOP로 인코딩
- **CrewAI**: 에이전트 = 역할 + 목표 + 도구 (도구만 바꾸면 도메인 전환)
- **AOS**: 스케줄러·컨텍스트·도구 관리를 레이어로 분리

---

## 현재 인스턴스

| 인스턴스 | 폴더 | 상태 |
|---|---|---|
| luma (콘텐츠 회사) | `30-projects/my-company/` | 운영 중 |
| 회계법인 (삼일PwC 레퍼런스) | `30-projects/accounting-firm/` | 구축 완료 |

> 각 인스턴스는 독립적 폴더에 존재하며 서로 영향을 주지 않는다.
```

---

## Phase 2 — 회계법인 인스턴스 (30-projects/accounting-firm/ 신규 폴더)

### 파일 9: 30-projects/accounting-firm/README.md
frontmatter: type=project, domain=accounting, source=claude, date=2026-03-20, status=active

내용:
- 삼일PwC(Samil PricewaterhouseCoopers)를 레퍼런스로 한 AI 회계법인 인스턴스
- my-company 템플릿에서 파생된 인스턴스 (domain.yaml inherit)
- 4개 서비스 라인: 감사(Assurance), 세무(Tax), 딜·자문(Deals/Advisory), 컨설팅(Consulting)
- PwC 글로벌 네트워크 멤버 (4대 회계법인 Big4)
- 파일 구조: domain.yaml / operations.md / workflows.md / stack.md
- 활용 Vault 자산: K-IFRS 기준서, 세법 원문, 감사기준서, 전문가 페르소나 13종

---

### 파일 10: 30-projects/accounting-firm/domain.yaml

```yaml
# AI 회계법인 — Domain Config
# Base: 30-projects/my-company/domain.yaml 상속 + 오버라이드

domain:
  name: 회계법인
  industry: accounting
  reference: "삼일PwC (Samil PricewaterhouseCoopers)"
  language: ko

agents:
  - role: Managing Partner
    persona: "법인 대표 — 전략·클라이언트 관계·품질 총괄"
    tools: [claude-code, notion, email]
  - role: Audit Partner
    persona: "감사 파트너 — Engagement 수락·감사의견 책임"
    tools: [claude-code, caseware, notion]
  - role: Tax Partner
    persona: "세무 파트너 — 세무신고·조사 대응·절세 전략"
    tools: [hometax-api, claude-code, notion]
  - role: Deals Partner
    persona: "딜 파트너 — M&A DD·밸류에이션·자문"
    tools: [excel-model, bloomberg, notion]
  - role: Audit Manager
    persona: "감사 매니저 — 팀 관리·현장 감독·KAM 식별"
    tools: [caseware, claude-code, notion]
  - role: Senior Associate
    persona: "시니어 — 감사 테스트 수행·문서화"
    tools: [caseware, excel, claude-code]
  - role: QC Reviewer
    persona: "EQCR — Engagement Quality Control Review 담당"
    tools: [caseware, claude-code]

workflows:
  - id: 01-external-audit
    name: 외부감사
    trigger: "event(engagement_accepted)"
    sop_file: sop/01-external-audit.md
  - id: 02-tax-filing
    name: 세무신고
    trigger: "cron(deadline-based)"
    sop_file: sop/02-tax-filing.md
  - id: 03-due-diligence
    name: "실사(DD)"
    trigger: "event(dd_request)"
    sop_file: sop/03-due-diligence.md
  - id: 04-advisory
    name: 자문 서비스
    trigger: "event(advisory_request)"
    sop_file: sop/04-advisory.md
  - id: 05-regulatory-response
    name: 감리 대응
    trigger: "event(regulatory_inquiry)"
    sop_file: sop/05-regulatory-response.md

tools:
  - name: "법제처 Open API"
    type: api
    purpose: 법령·고시 실시간 추적 (세법 개정 감지)
  - name: 홈택스 연동
    type: api
    purpose: 세무신고·납부 확인
  - name: "금감원 DART API"
    type: api
    purpose: 공시 자동 수집·분석
  - name: CaseWare
    type: saas
    purpose: 감사 조서 작성·문서화
  - name: Bloomberg
    type: saas
    purpose: 시장 데이터·밸류에이션
  - name: "은행 CSV 파서"
    type: cli
    purpose: 계좌 거래내역 자동 분류
  - name: "OCR 엔진 (Upstage)"
    type: api
    purpose: 재무제표·영수증 자동 인식
  - name: "ERP 연동 (SAP/더존)"
    type: api
    purpose: 회계 데이터 추출

escalation:
  - condition: 감사의견 변형 (한정·부적정·의견거절) 가능성
    action: "pause → Audit Partner 검토 → Managing Partner 보고"
  - condition: 세무신고 금액 10억 초과
    action: "pause → Tax Partner 이중 검토 → 클라이언트 확인"
  - condition: 감리 착수 통보
    action: "immediate_escalate → Managing Partner + 법률 자문"
  - condition: 독립성 위협 감지
    action: "pause → QC Reviewer → 독립성 위원회"
```

---

### 파일 11: 30-projects/accounting-firm/operations.md
frontmatter: type=project, domain=accounting, source=claude, date=2026-03-20, status=active

내용 (약 100줄):

**에이전트 현황 테이블**:
| 역할 | 서비스 라인 | 직급 | 주요 도구 |
|---|---|---|---|
| Managing Partner | 전 라인 | Partner | claude-code, notion |
| Audit Partner | 감사 | Partner | caseware, claude-code |
| EQCR | 감사(QC) | Partner/Director | caseware |
| Tax Partner | 세무 | Partner | hometax-api, claude-code |
| Deals Partner | 딜·자문 | Partner | bloomberg, excel |
| Audit Manager | 감사 | Manager | caseware, claude-code |
| Tax Manager | 세무 | Manager | hometax-api |
| Senior Associate | 감사/세무 | Senior | caseware, excel |
| Analyst | 딜 | Associate | bloomberg, excel |
| Operations Manager | 경영지원 | Manager | notion, spreadsheet |

**직급 체계** (삼일PwC):
Partner → Director → Senior Manager → Manager → Senior Associate → Associate

**Engagement 관리**:
- Engagement Letter 발행 → 팀 구성 → Budget 설정 (시간×직급별 단가)
- WIP (Work-In-Progress): 청구 전 누적 공수
- AR (Accounts Receivable): 청구 후 미수금
- 빌링 사이클: 월 1회 또는 마일스톤 기준

**타임시트 체계**:
- 일별 0.5h 단위 기록
- Charge code (Engagement 코드) 별 집계
- WIP 리포트: 주간 Manager 검토
- Realization rate: 실제 청구 / 투입 시간

**QC 프로세스**:
- Hot Review: 감사보고서 발행 전 EQCR 검토 (필수)
- Cold Review: 발행 후 품질 사후 검토 (표본)
- 독립성 확인: 연 1회 전체 + Engagement 착수 시
- 표준 조서 템플릿: 법인 내 표준화된 CaseWare 조서

---

### 파일 12: 30-projects/accounting-firm/workflows.md
frontmatter: type=project, domain=accounting, source=claude, date=2026-03-20, status=active

5개 워크플로우를 SOP 형식으로 (각 워크플로우마다 단계별 입력·처리·출력·에스컬레이션):

**WF-01: 외부감사 (External Audit)**
계획단계:
- Engagement 수락 의사결정 (독립성·리스크 평가)
- 감사팀 구성 (Partner-Manager-Senior-Staff)
- 중요성 금액 설정 (전체 중요성·수행 중요성)
- 위험 평가 (RMM: 왜곡표시 위험 식별)
현장실사:
- 내부통제 테스트 (통제 운영 효과성)
- 분석적 절차 (기대치 대비 편차 분석)
- 세부 테스트 (잔액·거래 증거 수집)
- 전문가 활용 (감정평가사·보험계리사 등)
보고단계:
- KAM (핵심감사사항) 식별 및 서술
- 감사 완료 절차 (사후사건 검토·경영진 확인서)
- EQCR (Hot Review)
- 감사보고서 발행
에스컬레이션: 의견 변형 가능성 → Audit Partner → Managing Partner

**WF-02: 세무신고 (Tax Filing)**
자료수집 → 세무조정 → 신고서 초안 → Tax Partner 검토 → 클라이언트 확인 → 전자신고 → 납부 확인
에스컬레이션: 신고 금액 10억 초과 또는 판단 불확실 조항

**WF-03: 실사 (Due Diligence)**
스코프 설정 → 재무DD(3-5년 재무제표 분석) → 세무DD(잠재 세무부채) → 리스크 정리 → 보고서
에스컬레이션: 중요 우발부채 발견 → 즉시 클라이언트 보고

**WF-04: 자문 서비스 (Advisory)**
자문 요청 수신 → 전문가 배정 → 이슈 분석 → 의견서 초안 → Partner 검토 → 납품
에스컬레이션: 법적 판단 필요 → 법률 자문사 협력

**WF-05: 감리 대응 (Regulatory Response)**
감리 착수 통보 수신 → 해당 Engagement 조서 점검 → 대응팀 구성 → 소명서 작성 → 감리위원회 제출 → 결과 대응
에스컬레이션: 즉시 → Managing Partner + 법률 자문 (감리 착수 시점)

---

### 파일 13: 30-projects/accounting-firm/stack.md
frontmatter: type=project, domain=accounting, source=claude, date=2026-03-20, status=active

내용:

# 회계법인 도구 스택

| 도구 | 유형 | 용도 | 우선순위 | 구현 현황 |
|---|---|---|---|---|
| 법제처 Open API | API | 법령·고시 실시간 추적 | P0 | 구현됨 |
| 홈택스 연동 | API | 세무신고·납부 확인 | P0 | 계획 |
| 금감원 DART API | API | 공시 자동 수집·분석 | P0 | 계획 |
| 국세청 전자신고 | Web | 법인세·부가세 신고 | P0 | 미결 |
| CaseWare | SaaS | 감사 조서·문서화 | P1 | 미결 |
| TeamMate+ | SaaS | 내부감사 관리 | P2 | 미결 |
| Bloomberg | SaaS | 시장 데이터·밸류에이션 | P1 | 미결 |
| Refinitiv Eikon | SaaS | 금융 데이터 | P2 | 미결 |
| 은행 CSV 파서 | CLI | 계좌 거래내역 분류 | P1 | 구현됨 |
| OCR 엔진 (Upstage) | API | 재무제표·영수증 인식 | P1 | 계획 |
| ERP 연동 (SAP) | API | 회계 데이터 추출 | P2 | 미결 |
| 더존 iCUBE 연동 | API | 국내 ERP 데이터 추출 | P1 | 미결 |
| Notion | SaaS | Engagement 관리·타임시트 | P1 | 구현됨 |
| Claude Code | CLI | 오케스트레이션·분석 | P0 | 구현됨 |

**도입 우선순위 근거**:
- P0: 법적 의무(신고·공시) 또는 핵심 운영에 직결
- P1: 감사 품질·효율에 직접 영향
- P2: 고급 기능, 추후 도입 가능

**현재 구현된 것 (Vault 자산 연계)**:
- 법제처 API: content-automation에서 세법 추적 구현
- 은행 CSV 파서: 기존 재무 분석 파이프라인 활용
- Notion: 운영 허브로 이미 사용 중
- Claude Code: 오케스트레이션 엔진으로 운영 중

---

## Execution Instructions
1. ssh luma2@m1 으로 Mac mini M1에 접속
2. /Users/luma2/vault/30-projects/ 하위 파일 생성
3. my-company/ 폴더에 domain.yaml, template-guide.md, sop/ 폴더 생성
4. accounting-firm/ 신규 폴더 생성 후 5개 파일 작성
5. my-company/biz-model.md 말미에 SOP-as-Template 섹션 추가 (기존 내용 유지)
6. 모든 파일에 YAML frontmatter 포함

## Done Criteria
- 13개 파일 모두 생성/수정 완료
- domain.yaml이 유효한 YAML 형식
- 각 SOP가 입력·처리·출력·에스컬레이션 구조 보유
- accounting-firm/이 my-company/와 독립적으로 존재
- biz-model.md 기존 내용 보존
