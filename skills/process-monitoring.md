Windows와 M4의 실행 중인 프로세스를 확인하고 정리한다. 다음 순서로 실행:

1. **Windows node 프로세스 확인**:
```bash
ps aux | grep -i "node" | grep -v grep | grep -v "Code\|claude\|eslint\|typescript\|copilot\|prettier"
```
각 PID의 cmdline을 확인해서 무엇인지 분류:
```bash
for pid in $(ps aux | grep -i "node" | grep -v grep | grep -v "Code\|claude\|eslint\|typescript\|copilot\|prettier" | awk '{print $1}'); do
  echo "PID $pid: $(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ' | head -c 200)"
done
```

2. **M4 주요 프로세스 확인**:
```bash
ssh m4 'source ~/.zshrc 2>/dev/null; echo "=== tmux ==="; tmux list-sessions 2>/dev/null; echo "=== node ==="; ps aux | grep "node " | grep -v grep | grep -v Code'
```

3. **M4 cron job 및 LaunchAgent 현황**:
```bash
ssh luma3@m4 "crontab -l"
```
```bash
ssh luma3@m4 "
LOGDIR=~/projects/agent-orchestration/logs
for log in \$LOGDIR/*.log; do
  name=\$(basename \$log .log)
  last_line=\$(tail -1 \$log 2>/dev/null)
  last_time=\$(stat -f '%Sm' -t '%m-%d %H:%M' \$log 2>/dev/null)
  echo \"\$name | \$last_time | \$last_line\"
done
"
```
```bash
ssh luma3@m4 "launchctl list | grep luma3 | awk '{print \$3, \$1}'"
```

4. 결과를 테이블로 정리:
   - 프로세스 이름, PID, 시작 시간, 상태
   - 불필요한 프로세스 표시 (좀비 dev 서버 등)
   - cron 표현식은 사람이 읽기 쉽게 변환 (예: `0 9 * * 1` → 매주 월 09:00)
   - LaunchAgent PID가 숫자면 ✅ 실행중, `-`면 ⚠️ 중단

5. 정리할 프로세스가 있으면 사용자에게 확인 후 kill
