세션을 마무리한다. 다음 단계를 순서대로 실행해라.

**경로 기준**: 모든 기기에서 `~/projects/agent-orchestration` 을 사용한다.
(Mac mini 등 다른 경로를 쓰는 기기는 `~/projects/agent-orchestration`으로 재클론 필요)

1. **오늘 daily 로그 업데이트**
   - 먼저 `hostname` 명령으로 현재 기기명을 확인해라. 기기명을 아래 규칙으로 레이블로 변환해라:
     - `MacBookAir` 포함 → `Mac Air`
     - `Macmini` 포함 → `Mac mini`
     - `DESKTOP` 포함 → `Windows`
     - 그 외 → `M4`
   - `~/projects/agent-orchestration/daily/[오늘날짜].md` 파일을 열어라.
   - 파일이 없으면 `~/projects/agent-orchestration/daily/TEMPLATE.md`를 참고해서 새로 만들어라.
   - 파일 맨 아래에 새 섹션을 추가해라 (기존 내용 수정 금지):

```
### 이번 세션에서 한 일 ([기기 레이블])
- (한 일 요약)

**블로커**
- (있으면)

**다음 세션에 이어할 것**
- (이어할 것)

---
```

2. **SCHEDULE.md 동기화**
   - `~/projects/agent-orchestration/SCHEDULE.md`를 읽어라.
   - 이번 세션에서 완료된 항목이 있으면 `[x]`로 체크해라.
   - 이번 세션에서 새로 발생한 할 일이 있으면 적절한 섹션에 추가해라.

3. **session.md 업데이트**
   - `~/projects/agent-orchestration/session.md` 파일을 열어라 (없으면 생성).
   - 맨 위에 아래 형식으로 이번 세션 요약을 추가해라 (이전 내용은 유지):

```
## [날짜 시간] ([기기 레이블])
**한 일**: (3줄 이내)
**진행 중**: (다음 세션에 이어할 것)
**주요 결정**: (있으면)
---
```

4. **book-journal.md 업데이트**
   - `~/projects/agent-orchestration/book-journal.md` 파일을 열어라 (없으면 생성).
   - 이번 세션에서 일어난 일을 바탕으로 아래 형식으로 맨 위에 추가해라 (이전 내용은 유지):

```
## [날짜 시간]
**AI가 한 것**: (Claude·Codex·Gemini가 실질적으로 처리한 것 — 1줄)
**사람이 한 것**: (AI가 못 하거나 안 한 것, 내가 직접 판단·결정한 것 — 1줄)
**의외의 순간**: (예상 밖이었던 것, 흥미로웠던 장면, 책에 쓸 만한 것 — 1줄. 없으면 생략)
---
```

   - 분량은 짧게. 억지로 채우지 말고, 없는 항목은 생략해라.
   - 이 파일은 "AI는 회계사를 대체할 수 있을까" 책의 날것 원고 재료다.

5. **Agent 설정 동기화**
   - 스크립트·설정 변경사항을 모든 에이전트(Claude/Codex/Gemini)에 배포해라:
     ```bash
     bash ~/projects/agent-orchestration/scripts/sync.sh
     ```
   - 실패하면 "sync.sh 실패: [에러 메시지]"를 출력하고 다음 단계로 넘어가라. 중단하지 마라.

6. **Git commit & push (전체 레포 스캔)**
   - `~/projects/` 아래 모든 git 레포를 순회하며 변경사항이 있는 것만 커밋·푸시해라.
   - 커밋 메시지 형식: `session: [날짜] [한 일 핵심 1줄]`
     예: `session: 2026-03-13 ICP 확정, book-journal 시스템 구축`
   - 실행 방법:
     ```bash
     for repo in ~/projects/*/; do
       if [ -d "$repo/.git" ] && { ! git -C "$repo" diff --quiet HEAD 2>/dev/null || git -C "$repo" status --porcelain 2>/dev/null | grep -q .; }; then
         echo "커밋: $repo"
         git -C "$repo" add -A
         git -C "$repo" commit -m "session: [날짜] [요약]"
         git -C "$repo" push
       fi
     done
     ```
   - 레포별로 변경 내용이 다르면 커밋 메시지를 각각 맞게 조정해라.
   - 변경사항 없는 레포는 건너뛰어라.

7. 완료 메시지 출력: "세션 마무리 완료. 다음 세션 시작 시 session.md를 먼저 읽어라."
