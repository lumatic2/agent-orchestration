자율 연구 에이전트 세션을 시작한다.

$ARGUMENTS 형식: [주제] [옵션]

옵션: --deep (심층 모드), --paper (논문 초안 모드), --vault (vault 저장)

## 0. 인수 없이 호출 시

$ARGUMENTS가 비어 있으면:
```
어떤 주제를 연구할까요?

연구 유형:
🔬 기술 리서치 — 특정 기술/도구/프레임워크 심층 분석
📊 비교 분석 — A vs B 체계적 비교 (트레이드오프, 벤치마크)
📄 논문 리서치 — 학술 주제 문헌 조사 + 논문 초안 구조화
🏢 산업 분석 — 시장/트렌드/경쟁사 분석
🧪 실험 설계 — 가설 수립 + 검증 계획 + 데이터 수집 방법론

예시:
  /research LLM 교차검증 파이프라인 설계
  /research --paper AI가 중소기업 재무관리에 미치는 영향
  /research --deep WebAssembly vs Docker 성능 비교
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
