투자봇 현황을 조회하고 분석한다. 다음 순서대로 실행해라:

0. M4 연결 확인 (실패 시 즉시 중단하고 "M4 오프라인" 보고):
```bash
ssh -o ConnectTimeout=3 m4 "echo ok" 2>/dev/null || echo "M4_OFFLINE"
```

1. 포트폴리오 현황을 조회한다 (통합 ScreeningStrategy 기반):
```bash
ssh m4 "cd ~/projects/investment-bot && python3 main_v2.py --mode status"
```

2. 전략 카탈로그 현황을 조회한다:
```bash
ssh m4 "cd ~/projects/investment-bot && python3 -c \"
import yaml
with open('config/strategies_catalog.yaml') as f:
    cat = yaml.safe_load(f)
strats = cat.get('strategies', {})
active = {k:v for k,v in strats.items() if v.get('enabled')}
warehouse = {k:v for k,v in strats.items() if not v.get('enabled')}
print('활성 포트폴리오 (%d개):' % len(active))
for k,v in active.items():
    w = v.get('target_weight', 0)
    cagr = v.get('backtest_cagr', 0)
    sharpe = v.get('backtest_sharpe', 0)
    role = v.get('role', '?')
    print(f'  {k:<25} {w:.0%}  CAGR={cagr:+.1f}%  Sharpe={sharpe:.2f}  [{role}]')
print(f'대기({len(warehouse)}): ' + ', '.join(warehouse.keys()))
\""
```

3. 봇 프로세스 및 최근 로그 확인:
```bash
ssh m4 "ps aux | grep main_v2 | grep -v grep | awk '{print \"PID:\", \$2, \"CPU:\", \$3\"%\", \"MEM:\", \$4\"%\"}'; echo '--- 최근 로그 ---'; tail -15 ~/projects/investment-bot/bot_v2.log 2>/dev/null | grep -v 'getUpdates'"
```

4. 아래 형식으로 출력해라:

---
**투자봇 현황 — [타임스탬프]**

**포트폴리오 (총 1.35억, ScreeningStrategy 통합)**
| 전략 | 비중 | NAV | 수익률 | 역할 | 엣지 |
|---|---|---|---|---|---|
| smallcap_quant | 20% | XX,XXX,XXX | +X.X% | satellite | fundamental |
| macd_us | 20% | XX,XXX,XXX | +X.X% | core | technical |
| seasonality_kr | 15% | XX,XXX,XXX | +X.X% | core | calendar |
| macd_signal | 15% | XX,XXX,XXX | +X.X% | satellite | technical |
| magic_formula_kr | 15% | XX,XXX,XXX | +X.X% | core | fundamental |
| leveraged_etf_200ma | 15% | XX,XXX,XXX | +X.X% | satellite | trend |

**시스템 상태**
- 엔진: HeartbeatEngine (main_v2.py --mode scheduler)
- 리밸런싱: 1월/7월 첫 거래일 (6개월 주기)
- 레버리지 ETF: 연말 매도 / 연초 재매수 (세금 최적화)
- 모드: PAPER (모의투자)
---

5. 에러가 있으면 원인을 분석하고 수정 방법을 제안한다.

**[사용자가 스크리닝 실행을 요청하면]**

6. 스크리닝 1회 실행:
```bash
ssh m4 "cd ~/projects/investment-bot && python3 main_v2.py --mode screening"
```

**[사용자가 전략 변경을 요청하면]**

7. 전략 활성화/비활성화: `config/strategies_catalog.yaml` 수정 후 봇 재시작.

**[사용자가 봇 재시작을 요청하면]**

8. M4 LaunchAgent 재시작:
```bash
ssh m4 "launchctl unload ~/Library/LaunchAgents/com.luma3.investment-bot.plist && launchctl load ~/Library/LaunchAgents/com.luma3.investment-bot.plist && echo 재시작완료"
```

**[사용자가 DART 캐시 갱신을 요청하면]**

9. 재무 데이터 + 주식수 + PER/PBR/배당 갱신:
```bash
ssh m4 "cd ~/projects/investment-bot && python3 -c \"
from data.fundamental_cache import fetch_and_cache
data = fetch_and_cache()
print(f'{len(data)}개 종목 재무 데이터 갱신 완료')
has_per = sum(1 for d in data.values() if d.get('per', 0) > 0)
has_div = sum(1 for d in data.values() if d.get('div', 0) > 0)
print(f'PER 있음: {has_per}개, 배당 있음: {has_div}개')
\""
```

**[사용자가 실전 투자 전환을 요청하면]**

10. 반드시 확인 단계를 거쳐라:
- "실제 돈이 투입됩니다. KIS 실계좌로 전환하려면 'live 전환 확인'이라고 입력하세요."
- 확인 후: `.env`에서 `KIS_IS_REAL=true`로 변경 + 봇 재시작

마지막에 물어봐라: "전략 변경, 스크리닝 실행, DART 갱신, 봇 재시작, 실전 전환이 필요하면 말해줘."
