# 실사용 예시 & 오케스트레이션 패턴

> 이 문서는 실제 운영 중 확인된 패턴과 프롬프트 예시를 정리한다.
> 이론이 아닌 실데이터 기반 — T001~T052+ 완료 작업 로그 기준.

---

## 1. 에이전트별 실사용 분포 (T001~T052 기준)

| 에이전트 | 태스크 수 | 주요 용도 |
|---|---|---|
| gemini | ~38건 | 리서치, 시장 분석, 문서 요약 |
| gemini-pro | ~8건 | 심층 분석, 경쟁사 분석, 재무 모델 |
| codex | ~4건 | 코드 생성, 스크립트 작성 |
| codex-spark | ~2건 | 빠른 편집, 포맷 변환 |

**관찰:** 리서치가 75%+. Codex는 코드 작업에만 집중.

---

## 2. 프롬프트 패턴 — 잘 작동한 것

### 2-1. 리서치 (Gemini)

```bash
# 단일 주제 리서치
bash orchestrate.sh gemini "argparse vs click vs typer 비교. Python CLI 라이브러리 선택 기준, GitHub stars, 학습곡선, 실무 적합성 정리해줘" routing-research

# 시장 규모 분석 (gemini-pro 사용)
bash orchestrate.sh gemini-pro "국내 치과 시장 규모. TAM/SAM/SOM 구조, 주요 플레이어, 디지털 전환 현황, 2024~2026 트렌드" dental-market-size

# 경쟁사 분석
bash orchestrate.sh gemini "덴탈 SaaS 국내 경쟁사 5개. 각사 제품, 가격, 타겟 고객, 강약점 비교표 형식으로" dental-competitor
```

**팁:** 결과물 형식("비교표", "bullet", "보고서 형식")을 명시하면 후처리 시간 절감.

### 2-2. 코드 생성 (Codex)

```bash
# Notion 배치 스크립트
bash orchestrate.sh codex "Python Notion API 스크립트. 데이터베이스에서 특정 조건 페이지 일괄 업데이트. 입력: DB ID + 필터 조건 + 업데이트 값" notion-batch-script

# 투자 봇 모듈 시리즈 (6개 순차 dispatching)
bash orchestrate.sh codex "투자봇 스케줄러 모듈. APScheduler 기반, 장 시작 전 5분 실행, 설정값 config.yaml에서 로드" invest-bot-scheduler
bash orchestrate.sh codex "투자봇 포트폴리오 관리 모듈. 현금+주식 합산 순자산, 리밸런싱 기준 20% 편차" invest-bot-portfolio
```

**팁:** 관련 모듈은 순서대로 dispatch. 이전 모듈의 인터페이스를 다음 brief에 명시.

### 2-3. 전문가 에이전트 (Skills)

```bash
# 세무 질의 → /tax skill
/tax TIPS 정부지원금 회계처리 방법 --planby

# 전문가 질의 → /expert skill (자동 라우팅)
/expert 스타트업 투자계약서의 주요 독소조항

# 콘텐츠 관리 → /content skill
/content
```

---

## 3. 파이프라인 패턴 — 검증된 흐름

### 3-1. Research → Code (E2E 파이프라인)

```
사용자 요청 → Gemini 리서치 → Claude 설계 결정 → Codex 구현 → Claude 검증
```

**실제 사례 (T001~T003):**
```bash
# Step 1: 라이브러리 리서치
bash orchestrate.sh gemini "Python CLI 라이브러리 비교. argparse vs click vs typer" routing-research-v1

# Step 2: Claude가 결과 검토 후 구현 지시
bash orchestrate.sh codex "orchestrate.sh에 --cost 플래그 추가. argparse 사용. 오늘 날짜 기준 에이전트별 태스크 수 집계" add-cost-flag
```

**소요 시간:** 리서치 3분 + 구현 8분 = 11분

### 3-2. 멀티모듈 직렬 개발

대형 코드 프로젝트는 모듈 단위로 나눠 순차 dispatch:

```bash
# 투자 봇 6모듈 순차 개발 (T019~T024)
invest-bot-skeleton  → invest-bot-scheduler → invest-bot-portfolio
→ invest-bot-momentum → invest-bot-execution → invest-bot-telegram
```

**팁:** 각 brief에 이전 모듈의 클래스/함수 시그니처 명시. Codex는 파일을 직접 읽으므로 작업 디렉토리 지정 필수.

### 3-3. 도메인 심층 분석 (병렬)

```bash
# 동시 dispatch — 독립적인 리서치 3개
bash orchestrate.sh gemini "치과 페인포인트 분석" dental-pain-points &
bash orchestrate.sh gemini "경쟁사 비교" dental-competitor &
bash orchestrate.sh gemini "규제 환경 분석" dental-regulation &
wait
# Claude가 3개 결과 통합 → 전략 문서 작성
```

---

## 4. 실패 패턴 & 대응

| 실패 유형 | 원인 | 대응 |
|---|---|---|
| Gemini rate limit (300/day) | Flash 할당량 초과 | gemini-pro로 전환 or 다음날 |
| Codex 작업 디렉토리 오류 | `--cwd` 미지정 | brief에 디렉토리 명시 |
| 너무 긴 태스크 → 품질 저하 | 한 번에 많은 것 요청 | 모듈 단위로 분리 |
| Gemini `--sandbox` 오류 | Docker 미설치 | `--sandbox` 플래그 제거 |
| Notion API 400 table_row | table_row 타입 직접 수정 불가 | insert-after로 table 뒤에 추가 |

---

## 5. 비용 효율 패턴

### 토큰 아낀 방법

- **Claude는 판단만**: 파일 탐색, 긴 문서 읽기 → Gemini에 위임
- **Gemini Flash 기본**: 300개/일 무료. Pro는 100개/일 아껴서 심층 분석만
- **Codex 우선**: 코드 생성은 Codex가 Claude보다 쿼터 여유 있음
- **세션 분리**: 긴 분석은 별도 세션으로 SHARED_MEMORY에 결과만 저장

### --cost로 사용량 확인

```bash
bash orchestrate.sh --cost          # 오늘
bash orchestrate.sh --cost week     # 최근 7일
bash orchestrate.sh --cost all      # 전체
```

---

## 6. 도메인별 실사용 기록

### 비즈니스 전략·재무 분석 (Planby Pilot)

복잡한 재무 분석 프로젝트에서 검증된 패턴:

```
Vault Knowledge (M1 vault 지식 베이스)
  → Notion API 직접 쿼리 (고객 DB, KPI DB)
  → Claude 통합 분석
  → Notion 페이지 업데이트 (notion_db.py)
```

**스크립트 연계:**
```bash
# 회사 문서 RAG 질의
bash scripts/planby_ask.sh "2025년 동시 진행 프로젝트 최대 몇 건이었나?"

# Notion DB 직접 조회
python3 ~/notion_db.py query-database <DB_ID> '{"property":"Status","select":{"equals":"Won"}}'

# 세무 질의 → /tax skill
/tax TIPS 기술기여도 계산 방법 --planby
```

### 법령 리서치

```bash
# 국가법령정보센터 + Gemini 조합
bash scripts/law_agent.sh "조특법 제29조의5 중소기업 통합고용세액공제 요건"
python3 scripts/law_search.py "기술기여도 계산 기준" --source TIPS
```

### 영상 편집

```bash
# 영상 편집 (FFmpeg)
bash scripts/video_edit.sh ai "4개 클립 머지 후 자막 추가하고 유튜브 포맷으로 출력"
```

---

## 7. 설정값 — 실전에서 조정한 것

`agent_config.yaml` 주요 설정:

```yaml
# Gemini: Flash 기본, 심층은 Pro
gemini_default: gemini-2.5-flash    # 300/day
gemini_heavy: gemini-2.5-pro        # 100/day — 아껴서 쓰기

# Codex: 코드 전용, 쿼터 여유 있음
codex_default: gpt-5.3-codex
codex_light: gpt-5.3-codex-spark    # 빠른 편집용

# 타임아웃 — 실전 조정값
dispatch_timeout: 300    # 5분 (복잡한 코드 생성은 더 걸림)
retry_delay: 30          # rate limit 시 대기
```

---

## 8. 새 기기 셋업 체크리스트

```bash
git clone https://github.com/Mod41529/agent-orchestration
cd agent-orchestration
bash scripts/sync.sh              # 설정 배포

# CLI 인증
codex --login                     # ChatGPT OAuth
gemini                            # Google OAuth (첫 실행 시 자동)

# Notion MCP
claude mcp add --scope user notion-personal -- npx -y @notionhq/notion-mcp-server
claude mcp add --scope user notion-company  -- npx -y @notionhq/notion-mcp-server

# 환경변수 (~/.zshenv)
export PERSONAL_NOTION_TOKEN=...
export COMPANY_NOTION_TOKEN=...

# 검증
bash orchestrate.sh --boot
bash orchestrate.sh gemini "테스트" test-task
```
