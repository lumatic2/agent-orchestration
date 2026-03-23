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

### Phase 1 — 스코핑 (Scoping)
1. 주제에서 핵심 연구 질문(RQ) 1~3개 도출
2. 연구 범위 정의 (포함/제외 기준)
3. 사용자에게 RQ + 범위 확인 요청 → 승인 후 Phase 2

### Phase 2 — 수집 + 교차검증 (Collection & Verification)
Gemini에게 리서치 위임 (`orchestrate.sh gemini`):

```
bash ~/projects/agent-orchestration/scripts/orchestrate.sh gemini "
## Research Brief
### Research Questions
{RQ 목록}

### Scope
{범위 정의}

### Instructions
1. 각 RQ에 대해 2+ 독립 소스에서 evidence 수집
2. 소스별 신뢰도 평가 (primary/secondary)
3. 교차검증: 소스 간 일치/불일치 명시
4. 각 finding에 confidence tier 부여:
   - **Strong**: 2+ primary sources, reproducible
   - **Moderate**: single reliable source, likely correct
   - **Speculative**: partial data, plausible but unverified
5. gap 분석: 답 못 찾은 영역 + 추가 조사 방향

### Stop Conditions
- 모든 RQ가 Moderate 이상으로 답변됨
- OR 추가 소스 없음 + 남은 gap 문서화 완료
" research-{주제요약}
```

### Phase 3 — 종합 + 산출물 (Synthesis)
Gemini 결과를 받아서:
1. **구조화된 리서치 노트** 작성 (아래 템플릿)
2. `--paper` 옵션 시: 논문 초안 구조까지 생성
3. `--vault` 옵션 시: vault `10-knowledge/{domain}/`에 저장

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

## Key Findings

### Finding 1: {제목}
- **Confidence**: Strong/Moderate/Speculative
- **Evidence**: {소스1}, {소스2}
- **Summary**: ...
- **Cross-check**: {소스 간 일치 여부}

### Finding 2: ...

## Contradictions & Open Questions
- {소스 간 불일치 사항}
- {답 못 찾은 영역}

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

2. vault `30-projects/papers/{주제}/` 에 저장:
   - `draft.md` — 논문 초안
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
