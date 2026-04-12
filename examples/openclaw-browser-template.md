# OpenClaw 브라우저 자동화 템플릿

> Phase 2에서 검증된 패턴. Claude Code → SSH → OpenClaw 에이전트 → 브라우저 실행 → Telegram 전송.
> 검증일: 2026-04-11

## 핵심 패턴

```bash
ssh luma3@luma3ui-Macmini.local \
  'PATH=/Users/luma3/.nvm/versions/node/v24.14.0/bin:$PATH \
   openclaw agent --agent main \
   --message "<작업 지시>" \
   --deliver \
   --reply-channel telegram \
   --reply-to 8556919856'
```

| 옵션 | 역할 |
|---|---|
| `--agent main` | 기본 에이전트 지정 |
| `--message` | 에이전트에게 전달할 작업 지시 |
| `--deliver` | 결과를 채널로 전송 |
| `--reply-channel telegram` | 결과 수신 채널 |
| `--reply-to 8556919856` | Telegram 사용자 ID |

**출력 구조**
- 텍스트 결과: SSH stdout → Claude Code 터미널에서 확인
- 스크린샷/이미지: `--deliver`로 Telegram에 자동 전송

---

## 주의: MCP `messages_send`와의 차이

| | `messages_send` (MCP) | `openclaw agent` (CLI) |
|---|---|---|
| 역할 | 아웃바운드 메시지 전송 | 에이전트 실행 + 도구 사용 |
| 에이전트 실행 | ❌ 봇 이름으로 문자만 전송 | ✅ AI가 브라우저·도구 실행 |
| 스크린샷 가능 | ❌ | ✅ |
| 사용 시점 | 사용자에게 알림 보낼 때 | 실제 작업을 위임할 때 |

---

## 템플릿 1 — 공개 페이지 데이터 수집

```bash
ssh luma3@luma3ui-Macmini.local \
  'PATH=/Users/luma3/.nvm/versions/node/v24.14.0/bin:$PATH \
   openclaw agent --agent main \
   --message "github.com/trending 페이지를 열고 오늘 상위 5개 레포 이름, 설명, 스타 수를 수집하고 스크린샷을 Telegram으로 보내줘." \
   --deliver --reply-channel telegram --reply-to 8556919856'
```

검증 결과 (2026-04-11): GitHub trending 구조화 텍스트 + 스크린샷 ✅

---

## 템플릿 2 — SPA (JS 렌더링 필요) 페이지

```bash
ssh luma3@luma3ui-Macmini.local \
  'PATH=/Users/luma3/.nvm/versions/node/v24.14.0/bin:$PATH \
   openclaw agent --agent main \
   --message "npmjs.com/package/react 페이지를 브라우저로 열어줘. 이 페이지는 JavaScript로 렌더링되는 SPA야. 페이지가 완전히 로드된 후 패키지 이름, 버전, 주간 다운로드 수, 설명을 수집하고 스크린샷을 Telegram으로 보내줘." \
   --deliver --reply-channel telegram --reply-to 8556919856'
```

검증 결과 (2026-04-11): react 19.2.5, 주간 다운로드 90,601,259 + 스크린샷 ✅

---

## 작업 지시 작성 팁

- SPA 페이지면 명시: `"이 페이지는 JavaScript로 렌더링되는 SPA야. 페이지가 완전히 로드된 후 ..."`
- 스크린샷 원하면 항상 명시: `"스크린샷을 찍어서 Telegram으로 보내줘"`
- 데이터 구조 지정 가능: `"이름, 버전, 다운로드 수를 목록 형태로 정리해줘"`
- 로그인 필요 페이지는 별도 인증 설정 필요 (현재 미검증)
