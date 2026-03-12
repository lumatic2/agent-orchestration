# SSH → Claude Code 자동 Bypass Permission 설정

SSH로 원격 접속 시 `claude` 명령이 자동으로 `--dangerously-skip-permissions` 모드로 실행되도록 설정하는 방법.

---

## 개요

**문제**: SSH 세션은 non-interactive shell로 시작되는 경우가 있어 `.bashrc`/`.zshrc`의 alias가 로드되지 않을 수 있음.

**해결**: 두 가지 레이어를 조합
1. **래퍼 스크립트** (`~/bin/claude`) — shell 종류/interactive 여부 무관하게 항상 동작
2. **alias** — interactive 세션 추가 보호

---

## Windows (SSH 서버) 설정

### 1. OpenSSH DefaultShell → Git Bash (login mode)

```powershell
# 관리자 권한 불필요 (PowerShell로 실행)
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value 'C:\Program Files\Git\bin\bash.exe' -PropertyType String -Force
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShellCommandOption -Value '--login' -PropertyType String -Force

# sshd 재시작 (설정 적용)
Restart-Service sshd
```

> **핵심**: `--login` 플래그로 bash가 `.bash_profile` → `.bashrc`를 로드함.

### 2. 래퍼 스크립트 생성

`~/bin/claude` (`C:\Users\1\bin\claude`) 에 생성:

```bash
#!/bin/bash
exec /c/Users/1/.local/bin/claude.exe --dangerously-skip-permissions "$@"
```

```bash
chmod +x ~/bin/claude
```

> `~/bin`이 `~/.local/bin`보다 PATH 앞에 위치해야 함. Windows 사용자 PATH에서 순서 확인.

### 3. cmd.exe 대비 래퍼 (선택)

`~/bin/claude.cmd` 생성:

```batch
@echo off
"C:\Users\1\.local\bin\claude.exe" --dangerously-skip-permissions %*
```

---

## macOS (SSH 서버) 설정

macOS는 OpenSSH가 기본적으로 사용자의 기본 셸을 login shell로 시작하므로 Windows처럼 레지스트리 설정 불필요.

### 1. 래퍼 스크립트 생성

```bash
mkdir -p ~/bin
cat > ~/bin/claude << 'EOF'
#!/bin/bash
exec /Users/<username>/.local/bin/claude --dangerously-skip-permissions "$@"
EOF
chmod +x ~/bin/claude
```

> `<username>`을 실제 사용자명으로 교체.

### 2. `.zshrc` 설정

```zsh
# PATH: ~/bin이 ~/.local/bin보다 앞에 와야 함
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"

# SSH 접속 시 alias 추가 보호
if [[ -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" ]]; then
    alias claude="claude --dangerously-skip-permissions"
fi
```

---

## 적용된 기기

| 기기 | OS | 상태 | 설정일 |
|---|---|---|---|
| Windows Desktop | Win 10 | ✅ 완료 | 2026-03-09 |
| MacBook Air M1 | macOS | ✅ 완료 | 2026-03-09 |
| Mac mini M4 | macOS | ⏳ 미완료 | — |

---

## M4 신규 기기 적용 체크리스트

```bash
# 1. claude 설치 확인
which claude || npm install -g @anthropic-ai/claude-code

# 2. 래퍼 스크립트
mkdir -p ~/bin
echo '#!/bin/bash
exec ~/.local/bin/claude --dangerously-skip-permissions "$@"' > ~/bin/claude
chmod +x ~/bin/claude

# 3. .zshrc에 PATH + alias 추가
echo '
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
if [[ -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" ]]; then
    alias claude="claude --dangerously-skip-permissions"
fi' >> ~/.zshrc

# 4. 테스트 (다른 기기에서 SSH 접속 후)
ssh m4 "which claude && claude --version"
```

---

## 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| alias 있는데 SSH에서 안 됨 | sshd 재시작 안 함 | `Restart-Service sshd` |
| 래퍼가 안 잡힘 | PATH 순서 문제 | `~/bin`이 `~/.local/bin`보다 앞인지 확인 |
| `.zshrc`에 이상한 값 들어감 | sed + 변수 확장 충돌 | heredoc (`<< 'EOF'`)으로 직접 작성 |
| macOS에서 bash 셸인데 alias 안 됨 | `.bash_profile`이 `.bashrc` 안 소싱 | `.bash_profile`에 `source ~/.bashrc` 추가 |
