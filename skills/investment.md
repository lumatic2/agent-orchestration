투자봇 현황을 조회하고 분석한다. 다음 순서대로 실행해라:

0. M1 연결 확인 (실패 시 즉시 중단하고 "M1 오프라인" 보고):
```bash
ssh -o ConnectTimeout=3 m1 "echo ok" 2>/dev/null || echo "M1_OFFLINE"
```

1. M1에서 최신 포트폴리오 스냅샷을 조회한다:
```bash
"cd ~/projects/investment-bot && python3 -c \"
import sys
sys.path.insert(0, '.')
from data.db.database import get_latest_snapshot
snap = get_latest_snapshot()
if snap:
    import json
    print(json.dumps(snap, indent=2, ensure_ascii=False, default=str))
else:
    print('No snapshot found')
\""
```

2. 아래 형식으로 출력해라:

---
**투자봇 현황 — [타임스탬프]**

**포트폴리오 요약**
| 항목 | 금액 |
|---|---|
| 총 평가금액 | X,XXX,XXX원 |
| 한국주식 | X,XXX,XXX원 |
| 미국주식 | X,XXX,XXX원 (환율 X,XXX.X) |
| 당일 손익 | +/-X,XXX원 (+/-X.XX%) |
| 누적 손익 | +/-X,XXX원 (+/-X.XX%) |

**스케줄 현황**
- 장 시작 알림: 평일 09:00 KST
- 매매 신호 체크: 평일 09:05 KST (DRY RUN)
- 장 마감 알림: 평일 15:35 KST
---

3. 최근 봇 로그 20줄을 확인한다:
```bash
"tail -20 ~/projects/investment-bot/error.log"
```

4. 에러가 있으면 원인을 분석하고 수정 방법을 제안한다.

5. 마지막에 물어봐라: "전략이나 종목, 스케줄 설정을 변경하고 싶으면 말해줘."

**[사용자가 특정 변경을 요청하면]**

6. 해당 파일을 M1에서 읽어 수정하고 서비스를 재시작한다:
```bash
"launchctl unload ~/Library/LaunchAgents/com.luma3.investment-bot.plist && launchctl load ~/Library/LaunchAgents/com.luma3.investment-bot.plist"
```
