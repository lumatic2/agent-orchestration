M4 cron job 및 LaunchAgent 현황을 조회한다. 다음 순서대로 실행해라:

1. M4 연결 확인 (실패 시 즉시 중단):
```bash
ssh -o ConnectTimeout=3 luma3@m4 "echo ok" 2>/dev/null || echo "M4_OFFLINE"
```

2. crontab 목록 조회:
```bash
ssh luma3@m4 "crontab -l"
```

3. 각 cron job의 마지막 실행 로그 확인:
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

4. LaunchAgents 실행 상태 확인:
```bash
ssh luma3@m4 "launchctl list | grep -E 'luma3|planby' | awk '{print \$3, \$1}'"
```

5. 아래 형식으로 출력해라:

---
**M4 자동화 현황 — [현재시각]**

**⏰ Cron Jobs**
| 이름 | 스케줄 | 마지막 실행 | 상태 |
|---|---|---|---|
| (job명) | (cron 표현식 → 사람이 읽기 쉬운 형태로 변환) | (날짜 시각) | ✅/⚠️ |

**🔧 LaunchAgents**
| 이름 | PID | 상태 |
|---|---|---|
| (agent명) | (pid 또는 -) | 실행중/중단 |

---

규칙:
- cron 표현식은 사람이 읽기 쉽게 변환 (예: `0 9 * * 1` → 매주 월 09:00)
- PID가 숫자면 ✅ 실행중, `-`면 ⚠️ 중단
- 로그 마지막 줄에 error/fail 포함 시 ⚠️ 표시
