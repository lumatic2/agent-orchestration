M4의 Claude Channel (텔레그램) 세션을 원격 제어한다.

$ARGUMENTS 형식: [command]

## 0. 인수 없이 호출 시 — 인터랙티브 모드

$ARGUMENTS가 비어 있으면 아래를 출력하고 사용자 선택을 기다려라:

```
📡 Claude Channel 컨트롤

1️⃣  status   — 세션 상태 확인 (alive/dead, 최근 대화)
2️⃣  logs     — 최근 대화 로그 보기
3️⃣  restart  — 세션 재시작 (hook/스킬 반영)
4️⃣  stop     — 세션 종료
5️⃣  start    — 새 세션 시작 (채널 모드)

번호 또는 명령어를 입력하세요.
```

## 1. status

M4 연결 확인 후 세션 상태를 조회한다.

```bash
ssh -o ConnectTimeout=3 m4 "echo ok" 2>/dev/null || echo "M4_OFFLINE"
```
M4_OFFLINE이면 "M4 오프라인" 보고 후 중단.

```bash
ssh m4 "/opt/homebrew/bin/tmux has-session -t claude-channel 2>/dev/null && echo 'SESSION_ALIVE' || echo 'SESSION_DEAD'"
```

SESSION_ALIVE면:
```bash
ssh m4 "/opt/homebrew/bin/tmux capture-pane -t claude-channel -p -S -5"
```

아래 형식으로 출력:
```
📡 Claude Channel — ✅ 실행 중
최근 활동:
  {capture-pane 마지막 5줄 요약}
```

SESSION_DEAD면:
```
📡 Claude Channel — ❌ 종료됨
`/channel start`로 시작할 수 있습니다.
```

## 2. logs

최근 대화 로그를 가져온다. $ARGUMENTS에 숫자가 있으면 해당 줄 수만큼.

```bash
ssh m4 "/opt/homebrew/bin/tmux capture-pane -t claude-channel -p -S -50"
```

텔레그램 메시지(`← telegram`)와 Claude 응답(`plugin:telegram:telegram - reply`)만 필터링해서 보기 좋게 정리해라.

형식:
```
📨 [사용자] 메시지 내용
🤖 [둥둥이] 응답 내용
```

## 3. restart

세션을 종료하고 재시작한다. hook/스킬 변경사항이 반영된다.

### 3-1. 현재 세션 ID 확보
```bash
ssh m4 "/opt/homebrew/bin/tmux capture-pane -t claude-channel -p -S -100"
```
출력에서 `claude --resume {session-id}` 패턴을 찾아 세션 ID를 추출한다.
없으면 resume 없이 새로 시작.

### 3-2. /exit 전송
```bash
ssh m4 "/opt/homebrew/bin/tmux send-keys -t claude-channel Escape"
```
1초 대기 후:
```bash
ssh m4 "/opt/homebrew/bin/tmux send-keys -t claude-channel '/exit' Enter"
```

### 3-3. 종료 대기 (최대 10초)
```bash
ssh m4 "for i in 1 2 3 4 5 6 7 8 9 10; do sleep 1; /opt/homebrew/bin/tmux capture-pane -t claude-channel -p -S -3 | grep -q '❯' && echo 'EXITED' && break; done"
```

### 3-4. 재시작
세션 ID가 있으면:
```bash
ssh m4 "/opt/homebrew/bin/tmux send-keys -t claude-channel 'claude --channels plugin:telegram@claude-plugins-official --resume {session-id}' Enter"
```

없으면:
```bash
ssh m4 "/opt/homebrew/bin/tmux send-keys -t claude-channel 'claude --channels plugin:telegram@claude-plugins-official' Enter"
```

### 3-5. 시작 확인 (5초 대기)
```bash
sleep 5
ssh m4 "/opt/homebrew/bin/tmux capture-pane -t claude-channel -p -S -5"
```

결과 출력:
```
📡 Claude Channel — 🔄 재시작 완료
세션 ID: {session-id 또는 "새 세션"}
```

## 4. stop

세션을 종료만 한다 (재시작 안 함).

```bash
ssh m4 "/opt/homebrew/bin/tmux send-keys -t claude-channel Escape"
```
1초 대기:
```bash
ssh m4 "/opt/homebrew/bin/tmux send-keys -t claude-channel '/exit' Enter"
```

```
📡 Claude Channel — ⏹️ 종료됨
```

## 5. start

종료된 상태에서 새로 시작한다.

먼저 tmux 세션 존재 여부 확인:
```bash
ssh m4 "/opt/homebrew/bin/tmux has-session -t claude-channel 2>/dev/null && echo 'EXISTS' || echo 'NOT_EXISTS'"
```

NOT_EXISTS면 tmux 세션부터 생성:
```bash
ssh m4 "/opt/homebrew/bin/tmux new-session -d -s claude-channel /bin/zsh -l"
```

이미 claude 프로세스가 실행 중인지 확인:
```bash
ssh m4 "/opt/homebrew/bin/tmux capture-pane -t claude-channel -p -S -3"
```
`❯` 프롬프트가 보이면 (쉘 대기 상태) claude 시작:
```bash
ssh m4 "/opt/homebrew/bin/tmux send-keys -t claude-channel 'claude --channels plugin:telegram@claude-plugins-official' Enter"
```

이미 claude가 실행 중이면 "이미 실행 중입니다. `/channel restart`를 사용하세요." 안내.

5초 대기 후 상태 확인:
```
📡 Claude Channel — ▶️ 시작됨
```
