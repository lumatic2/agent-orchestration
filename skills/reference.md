Behance 등 레퍼런스 사이트에서 모션 디자인 레퍼런스를 수집하고 vault에 저장한다.

## 실행

아래 명령을 실행해라:

```bash
ssh m4 "python3 ~/projects/behance_scraper.py" 2>&1
```

백그라운드로 실행하고 완료 알림을 기다려라.

## 완료 후

1. vault MCP로 `refs/remotion/index.md` 읽기
2. 수집 결과 요약 보고:
   - 사이트별 수집 수
   - 새로 추가된 레퍼런스 목록
   - 누적 총 레퍼런스 수

## 옵션

$ARGUMENTS 에 키워드가 있으면 해당 키워드만 수집:
```bash
ssh m4 "python3 ~/projects/behance_scraper.py --keyword '$ARGUMENTS'" 2>&1
```
