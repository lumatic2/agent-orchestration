~/projects/ 아래 git 레포의 변경사항을 커밋하고 푸시한다. 모든 병렬 세션 종료 후 한 세션에서만 실행해라.

1. **skills/ → commands/ 동기화**
   ```bash
   for f in ~/projects/agent-orchestration/skills/*.md; do
     [[ "$(basename "$f")" == *-public.md ]] && continue
     cp "$f" ~/.claude/commands/"$(basename "$f")"
   done
   ```

2. **변경사항 확인**
   - `~/projects/` 아래 git 레포를 순회하고, 변경사항이 있는 레포만 목록으로 보여줘라.
   - 각 레포의 `git status --short`와 `git diff --stat`을 출력해라.
   - SCHEDULE 파일(vault)은 obsidian-git이 자동 관리하므로 git에 포함하지 마라.

3. **안전 검사**
   - 스테이징 전 민감 파일 확인:
     ```bash
     git -C "$repo" status --short | grep -E '\.(env|db|sqlite3|key|pem)$' && echo "⚠️ 민감 파일 감지"
     ```
   - 최근 5분 내 다른 커밋이 있으면 경고:
     ```bash
     last=$(git -C "$repo" log -1 --format=%ct 2>/dev/null)
     now=$(date +%s)
     if [ $((now - last)) -lt 300 ]; then
       echo "⚠️ 최근 5분 내 다른 커밋 있음 — 충돌 확인 필요"
     fi
     ```
   - 민감 파일이 감지되면 커밋하지 말고 사용자에게 알려라.

4. **커밋 & 푸시**
   - **agent-orchestration**: 디렉토리 명시 스테이징 (`git add -A` 금지)
     ```bash
     git -C "$repo" add skills/ scripts/ configs/ templates/ adapters/ *.md
     ```
   - **다른 레포**: `.gitignore` 의존하되 `git add -A` 전 반드시 안전 검사 통과 확인
   - 커밋 메시지 형식: `session: [날짜] [한 일 핵심 1줄]`
   - 커밋 후 push. 변경사항 없는 레포는 건너뛰어라.

5. **결과 요약** 출력: 커밋된 레포 목록, 건너뛴 레포 목록, 경고 사항.
