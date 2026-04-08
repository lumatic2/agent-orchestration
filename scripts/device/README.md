# scripts/device/

기기별 수동 설치 파일. 여러 기기에 동일하게 필요하지만 sync.sh로 자동 배포하기엔
기기 의존성(경로·설치 방식)이 강한 것들을 템플릿으로 보관한다.

## codex-wrapper.sh.template

Codex CLI에 `--dangerously-bypass-approvals-and-sandbox` 플래그를 자동으로 붙이는 래퍼.

**배경**: 2026-04-08, M4(luma3)에 설치돼 있던 기존 래퍼에서 **무한 재귀 버그**가
발견됨. 래퍼가 `exec codex ...`로 자기 자신을 호출하면서 플래그를 무한히 누적해
sync.sh의 `check_agent "codex"` 단계를 hang시켰음. 원인은 래퍼가 `~/bin/codex`에
있고 `~/bin`이 실제 codex 바이너리 경로보다 PATH에서 앞에 오는 구조 때문에
`exec codex`가 자기 자신으로 resolve된 것. 절대 경로 사용으로 수정.

**설치 방법**:

```bash
# 1. 실제 codex 바이너리 경로 확인 (~/bin을 PATH에서 뺀 상태에서)
env -u PATH PATH="/opt/homebrew/bin:/usr/bin:/bin" which codex
# 또는
ls ~/.nvm/versions/node/*/bin/codex 2>/dev/null
ls /opt/homebrew/bin/codex 2>/dev/null

# 2. 템플릿 복사
cp ~/projects/agent-orchestration/scripts/device/codex-wrapper.sh.template ~/bin/codex

# 3. CODEX_BIN 값 편집 (__FILL_ME_IN__ 자리에 1단계 경로)
$EDITOR ~/bin/codex

# 4. 실행 권한
chmod +x ~/bin/codex

# 5. 검증 — 무한 재귀 없이 정상 종료되어야 함
~/bin/codex --version
```

**금지 사항**: 래퍼에 `exec codex ...` 쓰지 말 것. 반드시 `exec "$CODEX_BIN" ...`로
절대 경로 사용.

**현재 상태**:
- M4 (luma3): 설치됨 — 절대 경로 버전 (2026-04-08 수정 완료)
- Mac Air (luma2): 미설치 — `/opt/homebrew/bin/codex`가 brew 설치라 래퍼 불필요.
  brew 경로가 PATH 최상단이라 바이패스 플래그를 원하면 zsh alias 사용이 더 간단
- Windows (1): 미설치 — Codex 사용 시 사용자가 필요에 따라 직접 플래그 전달
