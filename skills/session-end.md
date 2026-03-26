세션을 마무리한다. 다음 단계를 순서대로 실행해라.

1. **Vault 40-log 기록**
   - `hostname` 명령으로 현재 기기명을 확인해라. 기기명을 아래 규칙으로 레이블로 변환해라:
     - `MacBookAir` 포함 → `Mac Air`
     - `Macmini` 포함 → `Mac mini`
     - `DESKTOP` 포함 → `Windows`
     - 그 외 → `M4`
   - `mcp__obsidian-vault__read_note("40-log/YYYY-MM-DD.md")` 로 오늘 로그 파일 확인.
   - 파일이 없으면 먼저 생성:
     ```
     mcp__obsidian-vault__write_note("40-log/YYYY-MM-DD.md",
       frontmatter={type: "log", date: "YYYY-MM-DD", status: "active"},
       content="# YYYY-MM-DD\n")
     ```
   - `mcp__obsidian-vault__write_note("40-log/YYYY-MM-DD.md", mode: "append")` 로 아래 형식 추가:
     ```
     ## 세션 [기기 레이블] HH:MM
     - 한 일: (3줄 이내)
     - 이어할 것: (다음 세션에 이어할 것)
     - 책 메모: (AI·자동화에서 책에 쓸 만한 장면 — 없으면 이 줄 생략)

     ---
     ```

2. **SCHEDULE.md 동기화**
   - `mcp__obsidian-vault__read_note("30-projects/schedule/SCHEDULE.md")` 로 읽어라.
   - 이번 세션에서 완료된 항목이 있으면 `mcp__obsidian-vault__patch_note` 로 `[x]`로 체크해라.
   - 이번 세션에서 새로 발생한 할 일이 있으면 적절한 섹션에 `patch_note`로 추가해라.

3. **스킬 파일 동기화 (skills/ → commands/)**
   - 이번 세션에서 `skills/*.md`를 수정했으면 commands/에 반영해라:
     ```bash
     for f in ~/projects/agent-orchestration/skills/*.md; do
       cp "$f" ~/.claude/commands/"$(basename "$f")"
     done
     ```
   - ⚠️ **스킬 파일은 반드시 `~/projects/agent-orchestration/skills/*.md`를 수정해라.** `~/.claude/commands/`는 배포 대상이므로 직접 수정 금지.

※ git commit/push는 이 스킬에서 하지 않는다. 모든 세션 종료 후 한 세션에서 `/push`를 실행해라.

완료 메시지 출력: "세션 마무리 완료. ✓ vault 40-log · SCHEDULE · skills sync"
