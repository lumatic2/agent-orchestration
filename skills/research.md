자율 연구 에이전트 세션을 시작한다.

$ARGUMENTS 형식: [주제] [옵션]

옵션: --deep (심층 모드), --paper (논문 초안 모드), --vault (vault 저장)

## 0. 인수 없이 호출 시

$ARGUMENTS가 비어 있으면 아래를 출력해라:

```
어떤 주제를 연구할까요?

연구 유형:
🔬 기술 리서치 — 특정 기술/도구/프레임워크 심층 분석
📊 비교 분석 — A vs B 체계적 비교 (트레이드오프, 벤치마크)
📄 논문 리서치 — 학술 주제 문헌 조사 + 논문 초안 구조화
🏢 산업 분석 — 시장/트렌드/경쟁사 분석
🧪 실험 설계 — 가설 수립 + 검증 계획 + 데이터 수집 방법론

──────────────────────────────────────────────
 모드 1  /research {주제}                  ← 기본
──────────────────────────────────────────────
절차: 스코핑(RQ 확인) → Gemini 리서치 → 종합
소요: 3~5분 / 사용자 개입 1회 (RQ 승인)
결과물: 구조화된 리서치 노트 (채팅창 출력, ~500~1000자)
  · RQ별 Key Findings (confidence 태그 포함)
  · 소스 간 교차검증 결과
  · Open Questions / 시사점

예시:
  /research WebAssembly vs Docker 성능 비교
  /research 국내 SaaS 스타트업 시장 규모 2024
  /research Claude API tool_use 동작 원리

──────────────────────────────────────────────
 모드 2  /research --vault {주제}
──────────────────────────────────────────────
모드 1과 동일 + vault 10-knowledge/{domain}/ 에 .md 파일로 저장
저장 경로 예: vault/10-knowledge/ai/llm-tool-use.md

──────────────────────────────────────────────
 모드 3  /research --paper {주제}
──────────────────────────────────────────────
절차: 스코핑 → Gemini 리서치 → 논문 초안 구조화
소요: 5~10분 / 사용자 개입 1회 (RQ 승인)
결과물: 리서치 노트 + 논문 초안 (채팅창 출력)
  · Abstract (~200단어)
  · Introduction / Related Work / Methodology
  · Findings / Discussion / Conclusion
  · References (소스 목록)
  총 분량: A4 3~5페이지 분량 마크다운
vault 30-projects/papers/{주제}/ 에 자동 저장:
  draft.md / notes.md / references.md

예시:
  /research --paper AI가 중소기업 재무관리에 미치는 영향
  /research --paper 멀티에이전트 시스템의 할루시네이션 제어 기법

──────────────────────────────────────────────
 모드 4  /research --paper --deep {주제}   ← 풀 파이프라인
──────────────────────────────────────────────
절차: 16단계 자동화 파이프라인
  S01 스코핑 → S02 arXiv+Semantic Scholar 논문 수집
  → S03 [GATE] 문헌 스크리닝 승인
  → S04~S05 지식 추출·종합
  → S09 [결정] PROCEED/REFINE/PIVOT
  → S10~S11 논문 초안 작성·수정
  → S12 [GATE] 품질 체크리스트 승인
  → S13~S14 최종 편집·인용 검증
  → S15 멀티에이전트 검증 (Gemini+Codex 독립 리뷰 → 자동 수정)
  → S16 PDF 생성 (Typst 템플릿 A/B/C/D)
소요: 30~60분 / 사용자 개입 2~3회 (게이트 승인)
결과물:
  · PDF 논문 (디자인 템플릿 선택 가능)
  · draft.md (A4 8~15페이지 분량 학술 논문)
  · 인용 검증 보고서 (arXiv DOI 실증)
  · S15 멀티에이전트 검증 리포트
특징: 실제 논문 API 기반 수집 → 할루시네이션 최소화

예시:
  /research --paper --deep LLM 기반 코드 자동 수정 시스템의 정확성
  /research --paper --deep 강화학습을 활용한 자율주행 경로 최적화
```

## 1. 연구 프로세스 (3단계 자율 루프)

### Phase 1 — 스코핑 + 쿼리 분해 (Scoping & Query Decomposition)
1. **관점 발견 (Perspective Discovery)**: 주제에서 탐색 가능한 관점 3~5개 도출 후 사용자에게 제시:
   - 관점 유형 예시: 기술적 원리 / 상업적 활용 / 역사적 맥락 / 비교·대안 / 한계·리스크 / 미래 전망
   - 예: "양자 컴퓨팅" → [기술 원리], [산업 적용], [국가별 경쟁], [보안 위협], [미래 로드맵]
   - 사용자가 관점을 선택하거나 "전부" / "기본"으로 수락 가능
2. 선택된 관점 기반으로 **핵심 연구 질문(RQ) 1~3개 도출**
3. 각 RQ를 **3~5개의 하위 질문(Sub-Q)**으로 분해:
   - Sub-Q 유형: 정의/개념, 핵심 메커니즘, 장점, 단점/한계, 비교/대안, 미래 전망
   - 예: "GPT-Researcher 아키텍처" → "Planner-Executor 구조란?", "병렬 크롤링 방식은?", "교차검증은 어떻게 하나?", "한계점은?" 등
4. Sub-Q를 바탕으로 **Annotated Outline** 생성:
   - 섹션 제목 + 해당 섹션에서 다룰 핵심 내용 1줄 요약
   - 예: `## 3. RAG 기반 완화 기법` → `외부 지식 베이스 연동으로 사실 정확도를 높이는 방법과 Self-RAG 발전 방향`
5. 사용자에게 관점 · RQ · Annotated Outline 확인 요청:
   - "승인" → Phase 2 진행
   - "수정" → Sub-Q 추가/제거, 섹션 변경, 관점 재선택 반영 후 재제시
   - 수정 없이 바로 진행 원하면 "넘어가자" / "응" 등으로 수락 가능

### Phase 2 — 수집 + 교차검증 (Collection & Verification)
Gemini에게 리서치 위임 (`orchestrate.sh gemini`):

```
bash ~/projects/agent-orchestration/scripts/orchestrate.sh gemini "
## Research Brief
### Research Questions
{RQ 목록}

### Sub-Questions (각 RQ별 하위 질문)
{Sub-Q 목록 — RQ별로 그룹화}

### Report Outline (이 구조에 맞춰 결과 작성)
{Phase 1에서 생성한 Annotated Outline — 섹션 제목 + 각 섹션 내용 요약 1줄}

### Instructions
1. 각 Sub-Q를 독립적으로 조사 — Sub-Q별로 2+ 독립 소스에서 evidence 수집
2. **URL 필수**: 모든 수치·사실 claim에 반드시 공식 문서 URL을 포함할 것
   - 형식: `[출처명](URL)` — URL 없는 수치는 자동으로 **Speculative**로 강등
   - 1차 소스 우선: 공식 API docs, 공식 changelog, 공식 블로그 직접 인용
   - URL을 찾을 수 없으면 해당 항목에 `[URL 미확인]` 태그 명시
3. 소스별 신뢰도 평가 (primary/secondary)
4. 교차검증: 동일 주제를 다룬 Sub-Q 결과 간 일치/불일치 명시
   - 2+ 소스에서 일관되면 Strong, 단일 소스면 Moderate, 추론이면 Speculative
5. 각 finding에 confidence tier 부여:
   - **Strong**: 2+ primary sources + URL 모두 확인됨
   - **Moderate**: single reliable source, URL 확인됨
   - **Speculative**: URL 미확인이거나 partial data
6. **불확실성 태그**: 동일 주제에 대해 상반된 주장을 하는 소스가 발견되면 해당 finding 옆에 `[불확실성: 상반된 관점 존재]` 태그를 명시하고, 양측 주장을 모두 기술
7. 결과를 Report Outline의 섹션 구조에 맞춰 작성 (섹션별로 관련 Sub-Q 결과를 채워 넣기)
8. gap 분석: 답 못 찾은 Sub-Q + 추가 조사 방향

### Stop Conditions
- 모든 Sub-Q가 Moderate 이상으로 답변됨
- OR 추가 소스 없음 + 남은 gap 문서화 완료
" research-{주제요약}
```

### Phase 3 — 종합 + 산출물 + 검증 (Synthesis & Verification)
Gemini 결과를 받아서:
1. **보고서 조립**: Phase 1 개요의 각 섹션에 Gemini 결과를 채워 넣어 완성
2. **구조화된 리서치 노트** 작성 (아래 템플릿)
3. **[S14 경량] 인용 검증**: 조립 완료 후 아래 명령으로 소스 목록 검증

```
bash ~/projects/agent-orchestration/scripts/orchestrate.sh gemini "
다음 리서치 결과의 Evidence/소스 목록을 검토해줘.
각 소스를 아래 기준으로 분류하라:
- ✅ OK — 제목·저자·연도·URL 모두 충분히 구체적
- ⚠️ Suspicious — 제목/저자가 모호하거나 검증 불가 수준으로 추상적
- ❌ No URL — URL 없이 출처명만 있어 추적 불가

분류 후:
- 미검증(Suspicious + No URL) 비율 계산
- 50% 초과 시 첫 줄에 [CITATION WARNING] 표기
- 각 소스별 한 줄 판정 + 개선 제안 출력

## 소스 목록
{보고서 Evidence 섹션 전체}
" citation-check-{주제요약}
```

- `[CITATION WARNING]` 발생 시: 사용자에게 알리고 계속 진행 여부 확인 후 진행
- 경고 없으면: 검증 결과를 보고서 하단 `## Citation Check` 섹션에 요약 추가

4. `--paper` 옵션 시: 논문 초안 구조까지 생성 → S11 섹션 보완 (아래 §3 참조)
5. `--vault` 옵션 시: 아래 규칙으로 vault `10-knowledge/{domain}/`에 저장

**domain 분류 규칙 (주제 키워드 매핑):**
| 키워드 | domain |
|---|---|
| llm, gpt, 딥러닝, 머신러닝, transformer, 강화학습, ai, 신경망, 임베딩, 멀티에이전트 | `ai` |
| react, python, rust, api, 코드, 아키텍처, 프레임워크, docker, kubernetes, 백엔드, 프론트엔드, 웹 | `dev` |
| 스타트업, 마케팅, 전략, okr, saas, 시장, 경영, 비즈니스, 투자, 재무 | `business` |
| 물리, 화학, 생물, 의학, 논문, 실험, 과학 | `science` |
| 그 외 | `general` |

**파일명 규칙:** `{주제-slug}.md`
- 주제를 소문자 + 하이픈으로 변환, 공백·특수문자 제거
- 예: "React Server Components 동작 원리" → `react-server-components-dong-jak-wonri.md`
- 날짜 불필요 (frontmatter date 필드에 기록됨)
- 충돌 시: `{slug}-2.md`
6. **자동 임시저장**: `--vault`나 `--paper` 옵션이 없어도, 리포트 완성 시 vault `00-inbox/{주제-slug}-{YYYY-MM-DD}.md` 에 자동 저장한다.
   - 저장 후: "→ vault/00-inbox/{파일명} 저장 완료" 한 줄 출력
   - 이미 존재하면 덮어쓰기

## 2. 리서치 노트 템플릿

```markdown
---
type: research
domain: {도메인}
source: auto-research
date: {날짜}
status: draft
confidence: {overall: strong/moderate/speculative}
---

# {주제}

## Research Questions
1. {RQ1}
2. {RQ2}

## Perspectives
- 선택된 관점: {관점1}, {관점2}, ...

## Report Outline
1. {섹션1} — {내용 요약 1줄}
2. {섹션2} — {내용 요약 1줄}
3. ...

## {섹션1 제목}

### Sub-Q: {관련 하위 질문}
- **Confidence**: Strong/Moderate/Speculative
- **Evidence**: {소스1}, {소스2}
- **Summary**: ...
- **Cross-check**: {소스 간 일치 여부 — 2+ 소스 일치 시 Strong 근거}
- **Uncertainty**: {상반된 관점이 있으면 `[불확실성: 상반된 관점 존재]` + 양측 요약, 없으면 생략}

## {섹션2 제목}

### Sub-Q: {관련 하위 질문}
- ...

## Contradictions & Open Questions
- {소스 간 불일치 사항}
- {답 못 찾은 Sub-Q}

## Implications
- {실행 가능한 시사점}

## Next Steps
- {추가 조사 필요 영역}
- {검증 필요 항목}
```

## 3. --paper 모드 (논문 초안)

Phase 3에서 추가로:
1. **논문 구조** 생성:
   - Abstract (200단어)
   - Introduction (배경 + 문제 정의 + RQ)
   - Related Work (기존 연구 정리)
   - Methodology (연구 방법)
   - Findings (핵심 발견)
   - Discussion (시사점 + 한계)
   - Conclusion
   - References

아래 Gemini 호출로 논문 초안을 생성한다:

```
bash ~/projects/agent-orchestration/scripts/orchestrate.sh gemini "
## Paper Draft Brief

### Topic
{주제}

### Research Questions
{RQ 목록}

### Research Findings
{Phase 3에서 조립된 보고서 전체}

### Instructions
아래 학술 논문 구조로 논문 초안을 작성해줘.

1. Abstract (200단어)
2. 1. 서론 (배경 + 문제 정의 + 연구 목적 + RQ)
3. 2. 관련 연구 (기존 연구 및 선행 문헌 정리)
4. 3. 연구 방법론 (분석 방법, 데이터 수집 방식)
5. 4. 연구 결과 (Phase 2 findings 기반, 섹션별 서술)
6. 5. 논의 (시사점 + 한계 + 향후 연구 방향)
7. 6. 결론
8. References (Phase 2 소스 목록 기반, (저자, 연도) 형식)

규칙:
- Phase 2 findings에 없는 내용 지어내기 금지
- 각 섹션 최소 200단어
- 전체 A4 3~5페이지 분량 마크다운
- 불확실성 태그([불확실성: 상반된 관점 존재])는 그대로 유지
" paper-draft-{주제요약}
```

2. **[S11] 섹션 보완**: 논문 초안 생성 직후 아래 명령으로 빈약한 섹션 자동 보완

```
bash ~/projects/agent-orchestration/scripts/orchestrate.sh gemini "
아래 논문 초안에서 분석이 얕거나 근거가 부족한 섹션 2~4개를 찾아 보완 단락을 작성해줘.

규칙:
- 기존 텍스트를 재출력하지 말 것 — 추가할 단락만 출력
- 각 보완은 150~300단어
- 기존 초안에 있는 근거/인용만 사용 (새 인용 지어내기 금지)
- 아래 형식으로만 출력:

## SECTION_ADDITION: {초안의 정확한 섹션 제목}
{해당 섹션 끝에 삽입할 보완 단락}

## SECTION_ADDITION: {다른 섹션 제목}
{보완 단락}

## 논문 초안
{생성된 논문 초안 전문}
" s11-expand-{주제요약}
```

- 반환된 각 `SECTION_ADDITION` 블록을 해당 섹션 끝에 삽입하여 초안 업데이트

3. vault `30-projects/papers/{주제}/` 에 저장:
   - `draft.md` — 논문 초안 (S11 보완 적용본)
   - `notes.md` — 리서치 노트
   - `references.md` — 참고문헌 목록

## 4. 주의사항

- 모든 claim에 소스 명시 (URL 또는 문서명)
- AI 추론은 반드시 Speculative로 태그
- 1차 소스(공식 문서, 논문, API docs)를 2차 소스(블로그, 포럼)보다 우선
- 수치/통계는 원본 출처 필수

## 5. --paper --deep 모드

`--paper`와 `--deep`가 함께 있으면 위 3단계 루프 대신 `scripts/research-pipeline.sh`를 호출한다.

### 5-1. 템플릿 선택

파이프라인 실행 전, 사용자에게 반드시 템플릿을 물어봐라:

```
PDF 템플릿을 선택해주세요:

A — Academic  (2단 컬럼, IEEE 스타일, 번호 있는 섹션)
B — Modern    (파란 배너 헤더, 사이드 액센트 라인)
C — Minimal   (넓은 여백, 명조체, 절제된 타이포그래피)
D — Tech Dark (다크 헤더 블록, 파란 액센트)

기본값: A
```

사용자가 선택하면 `--template {A|B|C|D}` 옵션으로 파이프라인을 호출한다.

### 5-2. 호출 규칙

```bash
bash ~/projects/agent-orchestration/scripts/research-pipeline.sh "{주제}" --template {A|B|C|D} [--skip-experiment]
```

**사전 요구사항 (S16 PDF 생성):**
- typst 설치 필수: `winget install typst` (Windows) / `brew install typst` (Mac)
- pandoc 설치 필수: `winget install pandoc` (Windows) / `brew install pandoc` (Mac)
- 미설치 시 S16에서 PDF 생성 실패 → draft.md만 최종 산출물로 대체
- 설치 확인: `typst --version && pandoc --version`

- vault `30-projects/papers/{topic-slug}/` 아래에 상태를 저장한다.
- `pipeline.json`이 이미 있으면 리줌한다 (5-4 참고).
- `--skip-experiment`가 있으면 S06-S08을 건너뛴다.

### 5-3. 게이트 프로토콜 (인터랙티브 루프)

파이프라인을 실행하고, exit code를 확인해 아래 루프를 반복한다:

```
exit 0  → 완료. 5-5로 이동.
exit 42 → 게이트 대기. 아래 절차 수행:
  1. pipeline.json을 읽어 gate_pending_stage 확인
  2. 해당 stage 파일을 읽어 핵심을 사용자에게 요약 (3-5줄)
  3. 사용자에게 승인 여부 질문: "계속 진행할까요? (y/n)"
  4a. 사용자가 y → --approve-gate {stage} 로 파이프라인 재시작 → 루프 반복
  4b. 사용자가 n → 파이프라인 중단, 이유 저장
exit 43 → 결정 대기. 아래 절차 수행:
  1. state/s09_decision.md를 읽어 사용자에게 요약
  2. PROCEED / REFINE / PIVOT 선택 요청
  3. --decide {선택} 로 재시작 → 루프 반복
그 외 → 에러 보고 후 중단
```

**게이트 대응 파일:**
- S03 게이트: `state/s03_screened.md` (문헌 스크리닝 결과)
- S06 게이트: `state/s06_experiment.md` (실험 설계)
- S12 게이트: `state/s12_quality.md` (품질 체크리스트)

**요약 형식:**
```
[S03 게이트 — 문헌 스크리닝]
수집 논문: N편 → 선별: M편
주요 논문: ...
제외 이유: ...

계속 진행할까요? (y/n)
```

### 5-4. 리줌 감지

파이프라인 호출 전, `pipeline.json` 존재 여부를 확인한다:

```bash
# slug = 주제를 소문자 하이픈으로 변환
PAPER_DIR=~/vault/30-projects/papers/{slug}
[ -f "$PAPER_DIR/pipeline.json" ] && echo "기존 파이프라인 발견"
```

- `pipeline.json`의 `status`가 `completed`가 아니면 → 리줌 여부를 사용자에게 물어라.
- 리줌 선택 시 → 동일 주제 + `--template` 옵션으로 재호출 (추가 플래그 불필요, 스크립트가 자동 감지).
- `completed` 상태면 → 결과 파일만 열어 요약 후 종료.

### 5-5. 완료 후 보고

완료되면 아래를 짧게 보고한다:

- 프로젝트 경로
- 생성된 PDF 경로 및 파일명
- 산출물: `draft.md`, `notes.md`, `references.md`
- S15 검증 결과 요약 (verdict, 자동 수정 여부)
