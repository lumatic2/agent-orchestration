# 원격 PC 깨우기 (휴대폰 → Telegram → M4 → WoL → Windows)

휴대폰이 셀룰러여서 집 LAN 밖이어도, 24시간 LAN 안에 있는 M4가 매직 패킷을 대신 쏴서
Windows PC를 절전에서 깨운 뒤 Chrome Remote Desktop으로 접속하는 파이프라인.

```
[Phone (셀룰러)] → Telegram → [M4 claude-channel] → bash wake-pc.sh
                                                       │
                                                       ▼ UDP 브로드캐스트 (LAN)
                                                  [Windows NIC] → 깨어남
                                                       │
                                                       ▼
                                              [Chrome Remote Desktop]
                                                       ▲
[Phone] ←──── Google relay ─────────────────────────────┘
```

## 대상 장비

| 항목 | 값 |
|---|---|
| 메인보드 | ASUS TUF GAMING X870E-PLUS WIFI7 |
| NIC | Realtek PCIe 2.5GbE Family Controller |
| MAC | `A0:AD:9F:B6:56:A0` |
| LAN IP | `192.168.200.191` (`/24`) |
| OS | Windows 11 Home |

## 설계 결정

- **절전(S3) 전용**: 완전 종료(S5)는 BIOS의 `ErP=Disabled` + `Power On By PCI-E=Enabled`
  가 필요하다. 매번 그것 때문에 재부팅하기 싫어 절전만 쓰는 경로 채택. 정전 직후엔
  현장 부팅 1회 필요.
- **자동 로그인 미사용**: 절전에서 깨면 이미 로그인 상태이므로 불필요. 대신 "절전 복귀 시
  비밀번호 요구"만 끔.
- **CRD vs Tailscale + Sunshine**: 일반 작업 용도라 저지연이 필수가 아님. CRD가 Google
  릴레이 거치므로 셀룰러에서 별도 VPN 없이 동작. (이 PC엔 Tailscale도 깔려 있어 향후
  대체 경로로 사용 가능.)

## Windows 설정 (1회)

관리자 PowerShell에서 일괄:

```powershell
# 1. 빠른 시작 OFF (절전 경로엔 무관하지만, S5 WoL 대비 미리 꺼둠)
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
  -Name HiberbootEnabled -Value 0 -Type DWord

# 2. netplwiz 자동로그인 체크박스 노출 (Win11 기본 숨김 해제)
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' `
  -Name DevicePasswordLessBuildVersion -Value 0 -Type DWord

# 3. 절전 복귀 시 비밀번호 요구 OFF (3겹: power scheme + group policy + attribute unhide)
$g = '0e796bdb-100d-47d6-a2d5-f7d2daa51f51'  # CONSOLELOCK
powercfg -attributes SUB_NONE $g -ATTRIB_HIDE
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE $g 0
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_NONE $g 0
powercfg /SETACTIVE SCHEME_CURRENT
$p = "HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\$g"
New-Item -Path $p -Force | Out-Null
Set-ItemProperty -Path $p -Name ACSettingIndex -Value 0 -Type DWord
Set-ItemProperty -Path $p -Name DCSettingIndex -Value 0 -Type DWord

# 4. ICMP echo 인바운드 허용 — M4(WoL 발사기)에서만. RemoteAddress로 좁혀서
#    게스트 Wi-Fi·다른 LAN 디바이스는 ping/스캔 못 하게 함.
$M4_IP = '192.168.200.134'
New-NetFirewallRule -DisplayName "Allow ICMPv4-In (WoL verify)" `
  -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow `
  -Profile Any -RemoteAddress $M4_IP
```

NIC의 WoL은 Realtek 2.5GbE 기본값이 `WakeOnMagicPacket=Enabled`라 별도 작업 불필요.
다른 보드면 다음으로 확인:

```powershell
Get-NetAdapterPowerManagement -Name '이더넷 2'  # WakeOnMagicPacket 컬럼
```

### Chrome Remote Desktop

1. https://remotedesktop.google.com/access (Chrome)
2. Google 로그인 → "원격 액세스 설정" → MSI 다운로드/설치
3. 컴퓨터 이름 + PIN 6자리

호스트가 Windows 서비스로 깔려 자동 시작. 절전 복귀 후 즉시 응답.

## M4 설정 (1회)

이 레포가 M4의 cron으로 매일 06:00 git pull 되므로 다음 한 번만 처리:

```bash
# scripts/wake-pc.sh를 ~/bin/에 심볼릭 링크 (git pull시 자동 반영)
ln -sf "$HOME/projects/agent-orchestration/scripts/wake-pc.sh" "$HOME/bin/wake-pc.sh"
chmod +x "$HOME/projects/agent-orchestration/scripts/wake-pc.sh"

# Telegram에서 /wake-pc 슬래시 명령으로 부르기 위한 파일
cat > "$HOME/.claude/commands/wake-pc.md" <<'MD'
---
description: Wake yusun Windows PC via Wake-on-LAN, then verify it came online
---

`bash ~/bin/wake-pc.sh` 를 실행해서 결과를 그대로 사용자에게 보여줘. 다음 사항만 확인:

- 매직 패킷 전송 성공 여부 (📨 라인)
- ping 응답 받았는지 (✅ 또는 ⚠️ 라인)
- 응답까지 걸린 시간

✅ 가 나오면 "PC 깨어남, CRD로 접속 가능" 이라고 짧게 알려주고 끝.
⚠️ 가 나오면 가능한 원인 (이미 깨어 있음 / 핑이 방화벽에 차단됨 / 정전·완전종료 상태) 만 한 줄로 안내.
추가 작업은 사용자 요청시에만.
MD

# 새 슬래시 명령이 인식되도록 claude-channel 세션 재시작
bash "$HOME/projects/agent-orchestration/scripts/start-claude-channel.sh"
```

### 다른 PC로 옮길 때

스크립트는 환경변수 `WAKE_MAC` / `WAKE_BROADCAST` / `WAKE_TARGET_IP` 를 읽어
default를 override한다. 두 번째 PC 추가하려면 wrapper 하나 더 만들기:

```bash
# ~/bin/wake-laptop.sh
#!/usr/bin/env bash
WAKE_MAC=11:22:33:44:55:66 \
WAKE_BROADCAST=192.168.200.255 \
WAKE_TARGET_IP=192.168.200.50 \
exec "$HOME/projects/agent-orchestration/scripts/wake-pc.sh"
```

스크립트 자체는 입력값 형식 검증(MAC/IPv4 정규식)을 하므로 오타 시 즉시 exit 2.

## 사용

1. Windows 절전 진입 (`Win+X` → 종료 또는 로그아웃 → 절전)
2. 휴대폰 Telegram → claude-channel 봇에 한 마디:
   - 슬래시: `/wake-pc`
   - 자연어: "내 PC 깨워줘"
3. ~5–30초 안에 `✅ 192.168.200.191 alive after ~Xs`
4. CRD 앱 → 컴퓨터 이름 → PIN 입력

## 참고: /channel 스킬 mismatch 정정

이 작업 중 발견. `~/.claude/commands/channel.md`가 tmux 세션명을 `telegram`으로 참조했지만
실제 세션은 `start-claude-channel.sh`가 `claude-channel`로 생성한다. 16곳 정정:

```bash
sed -i.bak \
  -e 's/-t telegram/-t claude-channel/g' \
  -e 's/-s telegram/-s claude-channel/g' \
  -e 's/tmux:telegram/tmux:claude-channel/g' \
  ~/.claude/commands/channel.md
```

플러그인 이름 (`plugin:telegram@...`, `bun.*telegram` 등)은 그대로 둔다. 정정 후
`/channel status/restart/stop/start` 모두 정상 동작.

> `commands/channel.md`는 setup.sh가 배포하지 않는 비-version-controlled 파일이라
> 이 정정은 M4에 직접 sed로 적용되었음. 다른 기기에서는 동일 sed를 다시 실행해야 함.

## 알려진 한계 (의도된 트레이드오프)

Codex adversarial-review에서 식별. 의식적 선택이라 즉시 fix 안 한 항목들.

- **S5(완전 종료) 복구 불가**: Windows Update 강제 재부팅·BSOD·정전 후엔
  절전이 아닌 S5 상태로 빠짐. 이 상태에서 NIC 대기전원이 끊겨 매직 패킷이
  NIC에 도달 못 함. 현재는 현장 수동 부팅 필요. 자동화 옵션 (미적용):
  (a) BIOS 진입 1회 — `ErP=Disabled` + `Power On By PCI-E=Enabled`,
  (b) 스마트플러그 + auto-boot 조합. → ROADMAP 참조.
- **"이미 깨어있음" 케이스의 의미론적 한계**: pre-check ping으로 `ℹ️
  already responsive` 출력해 transition 미관측을 명시하지만, 여전히 "확실히
  wake가 일어났다"는 강한 신호는 아님. 강화 신호 (CRD host service health,
  Tailscale agent ping 등)는 v2 검토.
- **Telegram trust boundary**: `claude-channel`이 wake 전용 채널이 아니라
  풀 Claude 세션(`--dangerously-skip-permissions`)이라, 봇 탈취 시 wake에
  그치지 않고 임의 명령 실행 가능. 이건 wake 자체와 분리된 별도 이니셔티브
  → ROADMAP 참조.

## 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| `📨 sent` 후 `⚠️ no ICMP after 120s` (exit 3) | wake 실패 또는 S5 상태 | "알려진 한계" 의 S5 항목 참조 |
| ping 차단 의심 | ICMP 룰이 RemoteAddress=M4_IP만 허용 | `Get-NetFirewallRule -DisplayName 'Allow ICMPv4-In (WoL verify)' \| Get-NetFirewallAddressFilter` 로 확인 |
| `❌ invalid MAC/BROADCAST/TARGET_IP` (exit 2) | env override 오타 | 환경변수 형식 재확인 (MAC `xx:xx:...`, IPv4 dotted) |
| CRD 연결되는데 화면이 잠금 상태 | CONSOLELOCK 설정이 안 먹음 | `powercfg -q SCHEME_CURRENT SUB_NONE 0e796bdb-100d-47d6-a2d5-f7d2daa51f51` 로 AC/DC=0 확인 |
| 슬래시 `/wake-pc` 인식 안 됨 | claude-channel 세션이 옛날 인덱스 보유 | `bash ~/projects/agent-orchestration/scripts/start-claude-channel.sh` |
