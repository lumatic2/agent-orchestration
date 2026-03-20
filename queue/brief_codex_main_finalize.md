# Task: agent-orchestration-Codex_main 마무리 작업 4종

## 작업 개요
`~/projects/agent-orchestration-Codex_main` 신규 repo의 남은 작업 4가지를 완료한다.
각 작업은 순서대로 실행한다.

---

## 작업 1: ROUTING_TABLE.md 생성 (새 repo)

### 목적
`agent-orchestration-Codex_main`에 상세 ROUTING_TABLE.md가 없다. 기존 것을 마이그레이션한다.

### 작업
1. `C:/Users/1/projects/agent-orchestration/ROUTING_TABLE.md` 읽기
2. Claude Code 전용 내용 제거/변환:
   - "Claude Code" → "Codex" (오케스트레이터 주체)
   - Claude subagent types (Haiku/Sonnet subagent) 항목 제거 또는 Codex 모델로 대체
   - Skill tool 관련 항목 제거
   - 경로: `~/projects/agent-orchestration/` → `~/projects/agent-orchestration-Codex_main/`
3. `C:/Users/1/projects/agent-orchestration-Codex_main/ROUTING_TABLE.md`로 저장

---

## 작업 2: adapters/codex_global.md 생성

### 목적
기존 repo가 `adapters/claude_global.md`를 원본으로 sync.sh가 배포하는 구조처럼,
새 repo도 `adapters/codex_global.md`를 원본 소스로 관리한다.

### 작업
1. `C:/Users/1/projects/agent-orchestration-Codex_main/AGENTS.md` 읽기
2. 상단에 아래 주석 헤더 추가:
   ```
   <!-- ⚠️ 원본 파일: adapters/codex_global.md (agent-orchestration-Codex_main 레포)
        ~/projects/agent-orchestration-Codex_main/AGENTS.md 는 sync.sh가 여기서 복사한 배포본 — 직접 편집 금지 -->
   ```
3. `C:/Users/1/projects/agent-orchestration-Codex_main/adapters/codex_global.md`로 저장
4. 기존 `AGENTS.md`에도 동일한 헤더 주석 추가

---

## 작업 3: sync.sh 업데이트

### 목적
`sync.sh`가 `agent-orchestration-Codex_main`을 인지하도록 추가한다.

### 작업 (파일: `C:/Users/1/projects/agent-orchestration/scripts/sync.sh`)

1. 파일 전체 읽기
2. `deploy_codex_brain()` 함수 또는 deploy 섹션을 찾아서,
   아래 내용을 추가하는 함수 `deploy_codex_main()` 작성:
   ```bash
   deploy_codex_main() {
     local dest_agents="$HOME/projects/agent-orchestration-Codex_main/AGENTS.md"
     local src="$REPO_DIR/../agent-orchestration-Codex_main/adapters/codex_global.md"
     if [ -f "$src" ]; then
       cp "$src" "$dest_agents"
       echo "[OK] codex_main AGENTS.md deployed"
     else
       echo "[WARN] codex_global.md not found, skipping codex_main deploy"
     fi
   }
   ```
3. main() 함수의 deploy 섹션 끝에 `deploy_codex_main` 호출 추가
4. `do_boot()`의 PULL_REPOS에 `agent-orchestration-Codex_main` 추가
   - 파일: `C:/Users/1/projects/agent-orchestration/scripts/orchestrate.sh`
   - Windows 섹션(`DESKTOP*|PC*|*windows*|LUMA*`)에 추가:
     `"$HOME/projects/agent-orchestration-Codex_main"`

---

## 작업 4: CLAUDE.md(adapters/claude_global.md) 업데이트

### 목적
기존 Claude Code 환경에서도 새 Codex_main repo의 존재를 인식하도록 Reference Files에 추가한다.
병행 운영 기간이므로 boot 경로는 기존 `agent-orchestration`을 유지한다.

### 작업
1. `C:/Users/1/projects/agent-orchestration/adapters/claude_global.md` 읽기 (없으면 `C:/Users/1/CLAUDE.md` 읽기)
2. `### Reference Files` 섹션에 아래 항목 추가:
   ```
   - **Codex-main repo**: `~/projects/agent-orchestration-Codex_main/` (Codex 오케스트레이터 신규 repo, 병행 운영 중)
   - **Codex AGENTS.md**: `~/projects/agent-orchestration-Codex_main/AGENTS.md`
   ```
3. 저장 후, `C:/Users/1/CLAUDE.md`에도 동일 내용 반영

---

## Done Criteria
- [ ] `agent-orchestration-Codex_main/ROUTING_TABLE.md` 생성 완료
- [ ] `agent-orchestration-Codex_main/adapters/codex_global.md` 생성 완료
- [ ] `agent-orchestration-Codex_main/AGENTS.md` 헤더 주석 추가 완료
- [ ] `agent-orchestration/scripts/sync.sh` — deploy_codex_main() 추가 완료
- [ ] `agent-orchestration/scripts/orchestrate.sh` — PULL_REPOS에 Codex_main 추가 완료
- [ ] `C:/Users/1/CLAUDE.md` Reference Files 업데이트 완료
- [ ] agent-orchestration-Codex_main repo git commit & push 완료
- [ ] agent-orchestration repo git commit & push 완료

## Constraints
- `agent-orchestration-Codex_main/adapters/` 디렉토리가 없으면 생성
- 기존 파일의 다른 내용은 수정 금지 (추가만)
- boot 경로(`orchestrate.sh --boot`)는 기존 `agent-orchestration` 유지
