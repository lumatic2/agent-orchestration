시스템 건강 상태를 점검하고, 문제가 있으면 수정/감사를 제안한다.

$ARGUMENTS가 있으면:
- `fix` → Phase 2(자동 수정)로 직행
- `audit` → Phase 3(시스템 감사)로 직행
- 없으면 → Phase 1(체크)부터 시작

---

## Phase 1: 현황 체크

다음 5개를 **병렬로** 실행해라:

1. **배포 파일 줄 수 예산**
```bash
echo "=== Line Budget (deployed) ===" && for pair in "$HOME/CLAUDE.md:120" "$HOME/.claude/orchestrator_rules.md:150" "$HOME/.codex/AGENTS.md:120" "$HOME/.gemini/GEMINI.md:150"; do f="${pair%%:*}"; b="${pair##*:}"; [ -f "$f" ] || continue; l=$(wc -l < "$f" | tr -d ' '); lbl=$(basename "$f"); if [ "$l" -gt "$b" ]; then echo "[WARN] $lbl: $l/$b"; else echo "[OK]   $lbl: $l/$b"; fi; done && echo "--- Source ---" && for pair in "SHARED_PRINCIPLES.md:50" "adapters/claude_global.md:120"; do f="${pair%%:*}"; b="${pair##*:}"; l=$(wc -l < "$HOME/projects/agent-orchestration/$f" 2>/dev/null | tr -d ' '); if [ "$l" -gt "$b" ]; then echo "[WARN] $f: $l/$b"; else echo "[OK]   $f: $l/$b"; fi; done
```

2. **MEMORY.md 줄 수** (200줄에서 잘림)
```bash
echo "=== MEMORY.md ===" && wc -l ~/.claude/projects/C--Users-1/memory/MEMORY.md 2>/dev/null && echo "Memory files:" && ls ~/.claude/projects/C--Users-1/memory/*.md 2>/dev/null | wc -l
```

3. **낡은 context/ 파일** (30일 이상 미수정)
```bash
echo "=== Stale context/ (30d+) ===" && find ~/projects/agent-orchestration/context/ -name "*.md" -mtime +30 -exec basename {} \; 2>/dev/null || echo "none"
```

4. **vault research/ 파일 수** (20개 초과 경고)
```bash
echo "=== vault research/ ===" && ssh -o ConnectTimeout=5 m4 "find ~/vault/10-knowledge/research -maxdepth 1 -name '*.md' -not -name '00-INDEX.md' | wc -l" 2>/dev/null || echo "SSH failed"
```

5. **skills ↔ commands 동기화**
```bash
echo "=== Skill Sync ===" && missing=0; drift=0; for f in ~/projects/agent-orchestration/skills/*.md; do b=$(basename "$f"); [[ "$b" == *-public.md ]] && continue; [ ! -f ~/.claude/commands/"$b" ] && echo "  MISSING: $b" && missing=$((missing+1)); done; for f in ~/.claude/commands/*.md; do b=$(basename "$f"); s=~/projects/agent-orchestration/skills/"$b"; [ ! -f "$s" ] && echo "  ORPHAN: $b" && drift=$((drift+1)); done; echo "Missing: $missing, Orphan: $drift"
```

6. **MEMORY.md stale 포인터** (삭제된 파일 참조)
```bash
echo "=== MEMORY stale pointers ===" && grep -oE '\(memory/[^)]+\)' ~/.claude/projects/C--Users-1/memory/MEMORY.md 2>/dev/null | tr -d '()' | while read p; do [ ! -f ~/.claude/projects/C--Users-1/"$p" ] && echo "  DEAD: $p"; done; grep -oE 'context/[a-z_-]+\.md' ~/.claude/projects/C--Users-1/memory/MEMORY.md 2>/dev/null | while read p; do [ ! -f ~/projects/agent-orchestration/"$p" ] && echo "  DEAD: $p"; done; echo "done"
```

7. **삭제된 파일 참조 (repo 활성 파일만)**
```bash
echo "=== Stale refs ===" && for ghost in SHARED_MEMORY ORCHESTRATION_SETUP; do refs=$(grep -rl "$ghost" ~/projects/agent-orchestration/{scripts,adapters,context,skills,README.md} 2>/dev/null | wc -l | tr -d ' '); [ "$refs" -gt 0 ] && echo "  [WARN] $ghost: $refs refs"; done; echo "done"
```

8. **queue/ 용량**
```bash
echo "=== Queue ===" && du -sh ~/projects/agent-orchestration/queue/ 2>/dev/null && find ~/projects/agent-orchestration/queue/ -name "*.md" 2>/dev/null | wc -l | xargs -I{} echo "{} files"
```

9. **vault 빈 도메인 + research/ 초과**
```bash
echo "=== Vault domains ===" && ssh -o ConnectTimeout=5 m4 "for d in ~/vault/10-knowledge/*/; do domain=\$(basename \"\$d\"); files=\$(ls \"\$d\"/*.md 2>/dev/null | grep -v 00-INDEX | wc -l | tr -d ' '); [ \"\$files\" -eq 0 ] && echo \"  EMPTY: \$domain\"; [ \"\$files\" -gt 20 ] && echo \"  OVER20: \$domain (\$files)\"; done" 2>/dev/null || echo "SSH failed"
```

### Phase 1 결과 해석

모든 결과를 테이블로 요약한 뒤, AskUserQuestion으로 다음 행동을 제안해라:

**WARN이 있으면:**
- 줄 수 초과 / 낡은 context / research 초과 / skill drift가 있으면 → "fix"와 "audit" 중 적절한 것을 옵션으로 제시
- 여러 문제가 동시에 있으면 → "fix 먼저 → audit" 순서 제안

**전부 OK면:**
- "시스템 건강합니다. audit(전체 감사)를 실행할까요?" 옵션 제시

---

## Phase 2: Fix (자동 수정)

사용자가 fix를 선택했을 때 실행. **자동으로 할 수 있는 것만** 처리:

1. **skills → commands 동기화**: MISSING인 스킬을 commands/에 복사
```bash
for f in ~/projects/agent-orchestration/skills/*.md; do
  b=$(basename "$f")
  [ ! -f ~/.claude/commands/"$b" ] && cp "$f" ~/.claude/commands/"$b" && echo "Copied: $b"
done
```

2. **vault research/ 정리**: 20개 초과 시, 파일명 패턴으로 도메인 분류 제안 (이동은 사용자 승인 후)
   - `it-contents-*`, `github-trends-*`, `events-*` → 유지 (cron 출력)
   - 나머지 → 파일명에서 도메인 추정 → 이동 제안

3. **ORPHAN commands 처리**: commands/에만 있고 skills/에 없는 파일 → 삭제 확인 AskUserQuestion

4. **MEMORY stale 포인터**: 삭제된 파일을 참조하는 MEMORY.md 항목 → 해당 줄 제거/수정

5. **삭제된 파일 참조**: SHARED_MEMORY 등 유령 참조가 활성 파일에 남아있으면 → 해당 줄 수정/제거

6. **빈 vault 도메인**: 파일 0개인 도메인 → 삭제 확인 AskUserQuestion

Phase 2 완료 후 → "audit도 실행할까요?" AskUserQuestion

---

## Phase 3: Audit (시스템 감사 — Opus 권장)

사용자가 audit를 선택했을 때 실행. 전체 시스템 아키텍처를 점검.

### Step 1: 컨텍스트 수집
다음을 읽어라 (Read/MCP):
- vault `00-System/SYSTEM_MAP.md`
- `~/projects/agent-orchestration/SHARED_PRINCIPLES.md`
- `~/projects/agent-orchestration/adapters/CLAUDE.md`
- `~/projects/agent-orchestration/adapters/claude_global.md`
- `~/projects/agent-orchestration/ROUTING_TABLE.md`

### Step 2: 분석 체크리스트
다음을 점검하고 발견 사항을 보고:

| 체크 항목 | 방법 |
|---|---|
| **어댑터 간 중복** | CLAUDE.md와 claude_global.md 사이 유사 내용 탐지 |
| **SYSTEM_MAP 정확성** | 실제 파일 구조와 MAP 내용 일치 여부 |
| **context/ 프로젝트 상태** | 각 context 파일 읽고 → 활성/보류/폐기 판단 제안 |
| **SHARED_PRINCIPLES 비대화** | 50줄 예산 대비 현황 + 워커에 불필요한 내용 없는지 |
| **vault 도메인 INDEX 정확성** | 각 도메인 00-INDEX.md가 실제 파일 목록과 일치하는지 (샘플 3개) |
| **낡은 규칙** | 더 이상 유효하지 않은 규칙, 폐기된 도구 참조 |

### Step 3: 보고 + 제안
발견 사항을 심각도(HIGH/MEDIUM/LOW)로 분류하고, 각각에 대해:
- **자동 수정 가능** → "수정할까요?" AskUserQuestion
- **판단 필요** → 선택지 제시 AskUserQuestion
- **대규모 리팩토링** → Plan mode 진입 제안

### Step 4: SYSTEM_MAP 갱신
감사 중 발견된 변경사항을 SYSTEM_MAP에 반영 (MCP write).
