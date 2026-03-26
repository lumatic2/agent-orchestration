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

3. **Git commit & push (코드/스크립트 레포만)**
   - `~/projects/` 아래 git 레포 중 **agent-orchestration** 등 코드/스크립트 레포만 커밋·푸시해라.
   - SCHEDULE 파일(vault)은 obsidian-git이 자동 관리하므로 git에 포함하지 마라.
   - ⚠️ **스킬 파일 편집 시**: 반드시 `~/projects/agent-orchestration/skills/*.md`를 수정해라. `~/.claude/commands/`는 배포 대상이므로 직접 수정 금지.
   - 커밋 메시지 형식: `session: [날짜] [한 일 핵심 1줄]`
     예: `session: 2026-03-19 스케줄 시스템 vault 이전`
   - 실행 방법 (commit만, push는 /push 스킬에서 별도 실행):
     ```bash
     for repo in ~/projects/*/; do
       if [ -d "$repo/.git" ] && { ! git -C "$repo" diff --quiet HEAD 2>/dev/null || git -C "$repo" status --porcelain 2>/dev/null | grep -q .; }; then
         echo "커밋: $repo"
         git -C "$repo" add -A
         git -C "$repo" commit -m "session: [날짜] [요약]"
       fi
     done
     ```
   - 변경사항 없는 레포는 건너뛰어라.
   - push는 하지 않는다. 필요 시 `/push` 스킬을 별도로 실행해라.

완료 메시지 출력: "세션 마무리 완료. ✓ vault 40-log · SCHEDULE · git"
