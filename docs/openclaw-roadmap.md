# OpenClaw 통합 로드맵

> Claude Code ↔ OpenClaw 연동. 브라우저 자동화·다채널·스케줄 등 Claude Code가 직접 못 하는 작업을 OpenClaw 에이전트에 위임하고 결과를 가져오는 구조.
> 작성: 2026-04-11

## 배경 및 목표

### 기존 스택 (2026-04-11 기준)

```
Claude Code (오케스트레이터)
  ├── codex-mcp  → Codex CLI 비동기 래퍼
  ├── gemini-mcp → Gemini CLI 비동기 래퍼
  └── Skills     → 고수준 UX 래퍼 (codex:rescue, gemini:research 등)
```

**한계**: 코드 작업·텍스트 리서치는 해결됐지만, 시각적 웹 작업(스크린샷, 클릭), 다채널 수신, 장시간 백그라운드 루프, 미디어 생성 등은 직접 불가.

### OpenClaw가 채우는 영역

| Claude Code 한계 | OpenClaw 해결 |
|---|---|
| 브라우저 없음 | Chromium 제어 (navigate, click, screenshot) |
| 채널 수신 없음 | Telegram·Discord·Slack 등 20개+ 채널 수신 |
| 스케줄링 없음 | 내장 cron |
| 미디어 생성 없음 | 이미지·TTS·음악·영상 |
| 단일 기기 | Nodes로 크로스 디바이스 |

### 연동 아키텍처

```
Claude Code
  └── openclaw-mcp (openclaw mcp serve)
        ├── messages_send  → OpenClaw 에이전트에게 작업 지시
        ├── events_wait    → 결과 올 때까지 대기
        └── messages_read  → 완료된 결과 회수

OpenClaw 에이전트 (내부 도구)
  ├── browser   → Chromium 제어
  ├── exec      → shell 실행
  ├── web_search / web_fetch
  ├── read/write/edit
  └── (codex-mcp + gemini-mcp 등록 시 Codex·Gemini도 호출 가능)
```

**핵심**: `openclaw mcp serve`는 대화 레이어(9개 도구)를 노출. Claude Code는 메시지를 보내고, OpenClaw 에이전트가 자신의 도구(browser 등)로 실행 후 결과를 돌려줌.

---

## Phase 1 — 설치 및 기본 연동 ✅ **등록 완료 (2026-04-11)**

**목표**: OpenClaw 게이트웨이를 띄우고 Claude Code에서 MCP로 연결.

### 완료된 작업

- M4(`luma3ui-Macmini.local`)에 OpenClaw 2026.4.5 이미 설치·실행 중 확인
- Gateway bind를 `loopback` → `lan`으로 변경 (tailscale.mode도 `off`로 변경)
  - M4 Gateway: `0.0.0.0:18789` (LAN 전체 오픈), Dashboard: `http://192.168.200.134:18789/`
- 인증 토큰을 `~/.openclaw/gateway.token`에 저장 (chmod 600)
- Windows `.claude.json` User MCPs에 `openclaw-mcp` 등록:
  ```json
  {
    "command": "ssh",
    "args": [
      "luma3@luma3ui-Macmini.local",
      "PATH=/Users/luma3/.nvm/versions/node/v24.14.0/bin:$PATH /Users/luma3/.nvm/versions/node/v24.14.0/bin/openclaw mcp serve --url ws://127.0.0.1:18789 --token-file /Users/luma3/.openclaw/gateway.token"
    ]
  }
  ```
- `/mcp` 목록에 `openclaw-mcp` 등록 확인 ✅

### 1-C 연결 검증 ✅ **완료 (2026-04-11)**

1. `conversations_list` 호출 → Telegram·webchat 대화 2개 확인 ✅
2. `messages_send`로 메시지 전송 → Telegram 수신 확인 ✅
3. Telegram에서 답장 → `events_wait`로 수신 확인 ✅

**완료 기준**: Claude Code → OpenClaw → Telegram 왕복 1회 성공. ✅

### 핵심 발견: MCP 도구 역할 구분

`messages_send`는 **아웃바운드 전용** — Claude Code가 봇 이름으로 Telegram에 메시지를 보내는 도구. 에이전트(AI)를 실행하지 않음.

실제 에이전트 실행(브라우저·도구 사용)은 SSH CLI로:
```bash
ssh luma3@luma3ui-Macmini.local \
  'PATH=/Users/luma3/.nvm/versions/node/v24.14.0/bin:$PATH \
   openclaw agent --agent main --message "..." --deliver \
   --reply-channel telegram --reply-to 8556919856'
```

---

## Phase 2 — 브라우저 자동화 실증

**목표**: Claude Code가 "특정 웹페이지를 보고 데이터를 가져와" 같은 시각 작업을 OpenClaw에 위임하는 실제 흐름 검증.

### 실제 실행 패턴 (1-C에서 확정)

```bash
# Claude Code → SSH → openclaw agent CLI → 브라우저 실행 → Telegram 전송
ssh luma3@luma3ui-Macmini.local \
  'PATH=/Users/luma3/.nvm/versions/node/v24.14.0/bin:$PATH \
   openclaw agent --agent main --message "<작업 지시>" \
   --deliver --reply-channel telegram --reply-to 8556919856'
```

- 텍스트 결과: SSH stdout으로 Claude Code에 반환
- 스크린샷: `--deliver`로 Telegram에 자동 전송 (Windows terminal 한계 극복)

### 2-A. 기본 스크린샷 플로우 ✅ **완료 (2026-04-11)**

GitHub trending 상위 5개 레포 수집 + 스크린샷 Telegram 전송 성공.

수집 결과 예시:
1. microsoft/markitdown — 99,768★
2. NousResearch/hermes-agent — 52,196★
3. coleam00/Archon — 15,659★
4. rowboatlabs/rowboat — 11,745★
5. multica-ai/multica — 6,128★

브라우저 플러그인: `group:automation` 활성화 상태 확인 (`~/.openclaw/openclaw.json`).

### 2-B. 실제 사용 시나리오 2가지 검증

**시나리오 A — 웹 데이터 추출** ✅ (2-A에서 검증 완료)
- GitHub trending (공개 페이지) 구조화 텍스트 반환 확인

**시나리오 B — 동적 페이지 (JS 렌더링 필요)** ✅ (2026-04-11)
- 타겟: `npmjs.com/package/react` (React SPA)
- 결과: react 19.2.5, 주간 다운로드 90,601,259 + 스크린샷 ✅
- Chromium이 JS 실행 후 정상 캡처 확인

### 2-C. 패턴 정리 ✅ **완료 (2026-04-11)**

`examples/openclaw-browser-template.md` 작성 완료.
- 공개 페이지 / SPA 페이지 2종 템플릿
- MCP `messages_send` vs CLI `openclaw agent` 차이 정리
- 작업 지시 작성 팁 포함

**완료 기준**: 브라우저 위임 → 스크린샷 + 텍스트 추출 2종 시나리오 성공. ✅

---

## Phase 3 — Telegram 양방향 연동 ✅ **완료 (2026-04-11)**

**목표**: Telegram으로 명령 → OpenClaw 실행 → 결과 Telegram 수신.

### 3-A. Telegram 채널 연결 ✅

Phase 1-C에서 이미 확인. Telegram 봇 연결 및 수신 동작 중.

### 3-B. 라우팅 규칙 설정 ✅

기본 상태는 바인딩 없음. 아래 명령으로 Telegram → main 에이전트 명시적 바인딩 추가:

```bash
ssh luma3@luma3ui-Macmini.local \
  'PATH=/Users/luma3/.nvm/versions/node/v24.14.0/bin:$PATH \
   openclaw agents bind --agent main --bind telegram'
```

결과: Telegram 메시지 수신 시 main 에이전트 자동 트리거 확인.
검증: "안녕" → 에이전트 응답 "안녕 유성. 오늘은 또 뭐 재밌는 거 만질까?" ✅

### 3-C. Webhook으로 Claude Code → OpenClaw 트리거 (선택 — 보류)

Phase 4·5 진행 중 실제로 필요해지면 그때 구현. 현재 SSH CLI 방식으로 동일 목적 달성 가능.

**완료 기준**: Telegram 메시지 → OpenClaw 에이전트 실행 → Telegram 응답 왕복 성공. ✅

---

## Phase 4 — OpenClaw에 Codex·Gemini MCP 등록 ✅ **완료 (2026-04-11)**

**목표**: OpenClaw 에이전트도 Codex·Gemini를 도구로 사용 가능하게. Telegram에서 "이 코드 리뷰해줘" → OpenClaw → Codex에 위임 → 결과 반환.

### 4-A. 기존 MCP 서버 등록 ✅

```bash
ssh luma3@luma3ui-Macmini.local 'PATH=... openclaw mcp set codex-mcp '"'"'{"command":"node","args":["/Users/luma3/projects/agent-orchestration/mcp-servers/codex-mcp/src/index.mjs"]}'"'"''
ssh luma3@luma3ui-Macmini.local 'PATH=... openclaw mcp set gemini-mcp '"'"'{"command":"node","args":["/Users/luma3/projects/agent-orchestration/mcp-servers/gemini-mcp/src/index.mjs"]}'"'"''
```

**트러블슈팅 기록**:
1. npm 의존성 없음 → M4에서 각 mcp-servers 디렉토리에 `npm install` 필요
2. codex-companion.mjs 없음 → M4는 Claude Code 미설치라 companion이 없음
   - 해결: Windows에서 `~/.claude/plugins/cache/openai-codex/codex/1.0.3/scripts/` 전체를 M4 동일 경로에 scp로 복사
   - `@openai/codex` npm 글로벌 설치도 필요 (`npm install -g @openai/codex`)
3. Gateway 재시작 필요: `openclaw gateway restart`

### 4-B. 풀 체인 검증 ✅

```
Telegram: "agent-orchestration 레포 최근 변경사항 리뷰해줘"
  → OpenClaw 에이전트 수신
  → codex_task(review) 호출
  → codex_result 회수
  → Telegram으로 리뷰 결과 전송
```

**완료 기준**: Telegram → OpenClaw → Codex MCP → 결과 → Telegram 체인 1회 성공. ✅

검증 결과 (2026-04-11): agent-orchestration 최근 커밋 리뷰 → Codex 분석 → Telegram 전송 성공.

---

## Phase 5 — 스케줄 루프 (기존 스크립트 이관) ✅ **완료 (2026-04-11)**

**목표**: Gemini API 의존 cron 스크립트를 OpenClaw 내장 cron으로 이관. Gemini API 불안정 해소, 각 채팅방별 분리 전송.

### 이관 결과

| OpenClaw cron | 스케줄 | 전송 채팅방 |
|---|---|---|
| `events-tracker` | 매주 월 08:00 | 행사 채팅방 |
| `it-contents` | 월·목·토 08:00 | IT 채팅방 |
| `accounting-news` | 화·금·일 09:00 | 회계 채팅방 |
| `github-trends` | 매주 수 08:00 | GitHub 채팅방 |

### 아키텍처 결정사항

- **youtube-topics**: 제거 (필요 없음)
- **events-tracker 역할 분리**: OpenClaw가 Telegram 알림 담당 / 기존 `events-tracker.sh`는 skku-hub API push 전담으로 유지 (Telegram 전송 비활성화)
- **content-bot** (`@NewsFairy_bot`): OpenClaw 채널로 등록, 기존 그룹 채팅방에 메시지 전송
- **RSS 소스**: `web_fetch`로 직접 fetch (브라우저 불필요). Google News는 search URL 대신 RSS URL 사용
- **시간 필터**: 24h → 48h (비일간 스케줄 간격 커버)

### 설정 관리

- **config 레포**: `lumatic2/openclaw-config` (private) — 각 cron 프롬프트·소스 파일로 버전 관리
- **관리 스킬**: `/openclaw` — Claude Code에서 현황 조회·즉시 실행·프롬프트 수정·스케줄 변경 가능

### 트러블슈팅 기록

- `content-bot` 계정 등록 필요: `openclaw channels add --channel telegram --account content-bot --token $TELEGRAM_BOT_TOKEN_IT`
- isolated cron 세션이 stuck될 경우: `openclaw gateway restart`로 해소
- M4 crontab 수정: SSH에서 `crontab -` 불가 (macOS Full Disk Access 제한) → M4 터미널에서 직접 `EDITOR=nano crontab -e` 필요

**완료 기준**: 4개 cron 등록 → 스케줄 실행 → 각 Telegram 채팅방 수신 성공. ✅

---

## 단계별 의존성

```
Phase 1 (설치·연결)
  └── Phase 2 (브라우저 자동화)
  └── Phase 3 (Telegram 연동)
        └── Phase 4 (Codex·Gemini 등록)
              └── Phase 5 (스케줄 이관)
```

Phase 2·3는 Phase 1 완료 후 병렬 진행 가능.

---

## 미확인 사항 (Phase 1 진행 중 검증 필요)

- [ ] `openclaw mcp serve`가 Gateway 없이도 동작하는지 (embedded fallback)
- [ ] `messages_send` → 브라우저 도구 사용 가능한 에이전트에 라우팅되는지
- [ ] `attachments_fetch`로 이미지(스크린샷) 실제 회수 가능한지
- [ ] Windows 네이티브 vs WSL2 중 어느 쪽이 더 안정적인지
- [ ] 기존 Telegram 봇 토큰을 그대로 재사용 가능한지

---

## 의도적으로 배제한 경로

- **Canvas**: macOS 전용. Windows 환경에서 불가
- **Voice Wake / Talk Mode**: 현재 필요 없음
- **OpenClaw 에이전트로 오케스트레이터 교체**: Claude Code가 오케스트레이터 역할 유지. OpenClaw는 Claude Code가 못 하는 작업 전담 워커로만 사용
