$ARGUMENTS 에 해당하는 항목을 완료 처리한다. 순서대로 실행해라.

1. **SCHEDULE.md 체크박스 업데이트**
   - ~/projects/agent-orchestration/SCHEDULE.md 를 읽어라.
   - $ARGUMENTS 와 가장 일치하는 항목을 찾아라 (부분 일치 허용).
   - 해당 항목의 `- [ ]` 를 `- [x]` 로 변경해라.

2. **Daily 로그 기록**
   - 오늘 날짜로 ~/projects/agent-orchestration/daily/YYYY-MM-DD.md 파일을 열어라.
   - 파일이 없으면 TEMPLATE.md 를 참고해서 새로 만들어라.
   - ## 완료 섹션에 `- [x] [우선순위] 항목명 #카테고리` 형식으로 추가해라.

3. **Notion 간트 차트 동기화 (best-effort)**
   - 아래 Python 코드를 실행해서 Notion 상태를 "완료됨"으로 업데이트해라.
   - 실패하면 에러 없이 넘어가라.

```bash
PYTHONIOENCODING=utf-8 python3 - <<'PYEOF'
import os, json, urllib.request, urllib.error
token = os.environ.get('PERSONAL_NOTION_TOKEN', '')
if not token:
    print('PERSONAL_NOTION_TOKEN 없음 — Notion 동기화 건너뜀')
    exit(0)
db_id = '30785046-ff55-81bc-b093-dfbd85d74ac5'
title_query = '$ARGUMENTS'
headers = {
    'Authorization': f'Bearer {token}',
    'Notion-Version': '2022-06-28',
    'Content-Type': 'application/json',
}
try:
    body = json.dumps({'filter': {'property': '이름', 'title': {'contains': title_query[:30]}}}).encode()
    req = urllib.request.Request(f'https://api.notion.com/v1/databases/{db_id}/query', data=body, headers=headers, method='POST')
    resp = json.load(urllib.request.urlopen(req, timeout=5))
    results = resp.get('results', [])
    if not results:
        print(f'Notion 매칭 없음: {title_query}')
        exit(0)
    page_id = results[0]['id']
    body2 = json.dumps({'properties': {'상태': {'status': {'name': '완료됨'}}}}).encode()
    req2 = urllib.request.Request(f'https://api.notion.com/v1/pages/{page_id}', data=body2, headers=headers, method='PATCH')
    urllib.request.urlopen(req2, timeout=5)
    print(f'Notion 동기화 완료 ✓')
except Exception as e:
    print(f'Notion 동기화 실패 (무시): {e}')
PYEOF
```

4. **완료 메시지 출력**
   - "완료: [항목명] → SCHEDULE.md 체크 + daily 로그 + Notion 동기화" 형식으로 출력.
