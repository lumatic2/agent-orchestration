콘텐츠 자동화 현황을 조회하고 파이프라인을 관리한다. 다음 순서대로 실행해라:

0. M1 연결 확인 (실패 시 즉시 중단하고 "M1 오프라인" 보고):
```bash
ssh -o ConnectTimeout=3 m1 "echo ok" 2>/dev/null || echo "M1_OFFLINE"
```

1. M1에서 최근 생성된 콘텐츠 아티팩트를 확인한다:
```bash
ssh m1 "ls -lt ~/Desktop/content-automation/outputs/ | head -10"
```

2. 아래 형식으로 출력해라:

---
**콘텐츠 자동화 현황**

**최근 생성 콘텐츠**
| 날짜 | 플랫폼 | 주제 | 상태 |
|---|---|---|---|
| ... | youtube/instagram | ... | approved/discarded |

**스케줄**
- 화/목/토 10:00 KST — 콘텐츠 생성 + Telegram 승인 요청
---

3. 사용자가 특정 아티팩트 파일을 보고 싶다면 JSON 내용을 읽어 요약해준다:
```bash
ssh m1 "cat ~/Desktop/content-automation/outputs/[파일명].json"
```

4. 사용자가 파이프라인을 수동 실행하고 싶다면:
```bash
# dry-run (Telegram/API 호출 없이 전체 흐름 검증)
ssh m1 "cd ~/Desktop/content-automation && python3 scheduler.py --dry-run --platform youtube"

# 실제 실행
ssh m1 "cd ~/Desktop/content-automation && python3 scheduler.py --platform youtube"
```

5. 마지막에 물어봐라: "주제 변경, 플랫폼 추가, 스케줄 수정이 필요하면 말해줘."
