투자봇 현황을 조회하고 분석한다. 다음 순서대로 실행해라:

0. M4 연결 확인 (실패 시 즉시 중단하고 "M4 오프라인" 보고):
```bash
ssh -o ConnectTimeout=3 m4 "echo ok" 2>/dev/null || echo "M4_OFFLINE"
```

1. M4에서 투자봇 상태를 조회한다:
```bash
ssh m4 "cd ~/projects/investment-bot && python3 -c \"
import sys, json
sys.path.insert(0, '.')
try:
    from data.db.database import get_latest_snapshot
    snap = get_latest_snapshot()
    print(json.dumps(snap, indent=2, ensure_ascii=False, default=str) if snap else 'No snapshot')
except Exception as e:
    print(f'Error: {e}')
\""
```

2. 전략 현황을 조회한다:
```bash
ssh m4 "cd ~/projects/investment-bot && python3 -c \"
import yaml
with open('config/strategies_catalog.yaml') as f:
    cat = yaml.safe_load(f)
active = [k for k,v in cat['strategies'].items() if v.get('enabled')]
inactive = [k for k,v in cat['strategies'].items() if not v.get('enabled')]
print(f'활성({len(active)}): ' + ', '.join(active))
print(f'창고({len(inactive)}): ' + ', '.join(inactive))
\""
```

3. 최근 봇 로그를 확인한다:
```bash
ssh m4 "tail -20 ~/projects/investment-bot/error_v2.log 2>/dev/null || tail -20 ~/projects/investment-bot/error.log 2>/dev/null"
```

4. 아래 형식으로 출력해라:

---
**투자봇 현황 — [타임스탬프]**

**포트폴리오 요약**
| 항목 | 금액 |
|---|---|
| 총 평가금액 | X,XXX,XXX원 |
| 한국주식 | X,XXX,XXX원 |
| 미국주식 | X,XXX,XXX원 |
| 당일 손익 | +/-X,XXX원 (+/-X.XX%) |
| 누적 손익 | +/-X,XXX원 (+/-X.XX%) |

**전략 현황**
- 활성 (6개): golden_cross, momentum, rsi_reversal, all_weather, magic_formula_kr, macd_us
- 창고 (27개): [비활성 목록]

**봇 스케줄 (M4 LaunchAgent)**
- 장 시작 알림: 평일 09:00 KST
- 매매 신호 체크: 평일 09:05 KST
- 장 마감 알림: 평일 15:35 KST
- 모드: PAPER (모의투자)
---

5. 에러가 있으면 원인을 분석하고 수정 방법을 제안한다.

**[사용자가 전략 변경을 요청하면]**

6. 전략 활성화/비활성화:
```bash
ssh m4 "cd ~/projects/investment-bot && python3 -c \"
import yaml
path = 'config/strategies_catalog.yaml'
with open(path) as f:
    cat = yaml.safe_load(f)
# cat['strategies']['전략명']['enabled'] = True/False
with open(path, 'w') as f:
    yaml.dump(cat, f, allow_unicode=True, default_flow_style=False)
print('변경 완료')
\""
```

**[사용자가 봇 재시작을 요청하면]**

7. M4 LaunchAgent 재시작:
```bash
ssh m4 "launchctl unload ~/Library/LaunchAgents/com.luma3.investment-bot.plist && launchctl load ~/Library/LaunchAgents/com.luma3.investment-bot.plist && echo 재시작완료"
```

**[사용자가 실전 투자 전환을 요청하면]**

8. 반드시 확인 단계를 거쳐라:
- "⚠️ 실제 돈이 투입됩니다. KIS 실계좌로 전환하려면 'live 전환 확인'이라고 입력하세요."
- 확인 후: `.env`에서 `KIS_IS_REAL=true`로 변경 + 봇 재시작

마지막에 물어봐라: "전략 활성화·비활성화, 종목·스케줄 변경, 실전 전환이 필요하면 말해줘."
