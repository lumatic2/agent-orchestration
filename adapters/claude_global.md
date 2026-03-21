# Claude Code — Global Instructions
<!-- ⚠️ 원본 파일: adapters/claude_global.md (agent-orchestration 레포)
     ~/CLAUDE.md 는 sync.sh가 여기서 복사한 배포본 — 직접 편집 금지 -->

## 기본 규칙

- 한국어로 소통
- 간결하게 응답

## 모델 라우팅 규칙 (엄격 모드)

질문의 복잡도를 판단하여 현재 설정이 부적절하면 추천:

**Sonnet (오케스트레이터 판단 용도만)**
- 1-3파일, <50줄의 단순 수정만 직접 수행
- 작업: 파일 조회, 단순 편집, 위임 판단, 결과 검수
- 금지: 버그 수정, 기능 구현, 리팩토링
- 예: "README 첫 줄 수정"은 직접 수행 / "버그 고쳐줘"는 Codex 위임

**Opus (전략/시스템 설계만)**
- 사용: 오케스트레이션 아키텍처, 시스템 점검, 장기 전략
- 사용 빈도: 월 5-10회 수준으로 제한
- 절대 금지: 코드 생성, 문서 작성, 일상 판단
- 예: "토큰 절약 시스템 재설계"는 Opus / "이 task는 Codex 위임 맞나?"는 Sonnet

**Codex (코딩/분석 중심)**
- 4+ 파일, 50+ 줄, 모든 구현/리팩토링 작업 담당
- 코드 리뷰, 에러 분석, 데이터 처리 우선 담당
- 캐싱 효율 80%+ 유지가 목표이므로 최우선 활용

**Gemini (리서치/문서 분석)**
- 웹 검색이 필요한 모든 리서치 담당
- 50+ 페이지 문서 요약/분석 담당
- 배치 작업(대량 콘텐츠 수집, 크롤링) 우선 담당
- 일 1500 한도 대비 저활용 구간을 해소하도록 적극 사용

현재 모델이 부적절하면 세션 시작 시 한 번만 안내:
"이 작업은 [모델]이 적합해요. `/model [모델]`로 바꾸시겠어요?"

---


## FIRST ACTION (Every Session, No Exceptions)

```bash
bash ~/projects/agent-orchestration/scripts/orchestrate.sh --boot
```

Then apply the Self-Execution Guard before writing a single line of code:

| Condition | Action |
|---|---|
| 50+ lines of code to write | STOP → `orchestrate.sh codex "task" name` |
| 4+ files to create/modify | STOP → `orchestrate.sh codex "task" name` |
| Any research needed | STOP → `orchestrate.sh gemini "task" name` |
| Simple edit (1-3 files, <50 lines) | Proceed directly |

> ⚠️ **리서치 위임 방법**: 반드시 `Bash("bash ~/projects/agent-orchestration/scripts/orchestrate.sh gemini \"task\" name")` 직접 호출.
> `Agent(subagent_type="gemini-researcher")` 사용 **금지** — 위임 루프 버그로 실제 리서치를 수행하지 않음.

Examples:
- "지뢰찾기 게임 만들어줘" → Python ~100줄 → **`orchestrate.sh codex`로 위임**
- "README 첫 줄 수정" → 1파일 1줄 → 직접 수행
- "이 라이브러리 최신 버전 찾아줘" → 리서치 → **`orchestrate.sh gemini`로 위임**

상세 오케스트레이션 규칙 (Pre-flight, Multi-Agent, Routing, Handoff, Queue) → `/orchestrate` 스킬 참조.

---

## Knowledge Vault

- **Location**: `luma2@m1:~/vault/` (MCP: `obsidian-vault`)
- **Entry point**: `00-System/VAULT_INDEX.md` — 에이전트가 vault 작업 전 반드시 읽을 것
- **쓰기 권한**: **MCP `obsidian-vault` 또는 M1 직접** — 다른 기기에서 쓸 때는 MCP 사용
  - 로컬 vault clone 금지 (혼동 방지 — Windows vault는 삭제됨)
- **Write rules**:
  - 리서치 결과 → `10-knowledge/{domain}/`
  - 전문가 AI 업데이트 → `20-experts/{name}.md`
  - 프로젝트 노트 → `30-projects/{project}/`
  - 미분류/급할 때 → `00-inbox/`
  - 날짜 로그 → `40-log/YYYY-MM-DD.md` (session-end 자동 기록)
- **Frontmatter 필수**: type, domain, source, date, status
- Gemini 리서치 완료 후 → vault에 저장 (SHARED_MEMORY.md 덮어쓰기 금지)
