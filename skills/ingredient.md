식재료 재고 현황을 조회하고 분석한다. 다음 순서대로 실행해라:

1. M1에 SSH로 접속해서 재고 현황을 가져와라:
   ```
   ssh m1 "cd ~/ingredient-bot && python3 -c \"
from db import IngredientDB
from dotenv import load_dotenv
load_dotenv()
db = IngredientDB()
items = db.list_ingredients()
low = db.get_low_stock_and_expiring(days=5)
shopping = db.list_shopping_items()
print('=== 전체 재고 ===')
for i in items: print(f'{i[\"name\"]}: {i[\"quantity\"]}{i[\"unit\"]} | 유통기한: {i.get(\"expiry_date\",\"없음\")}')
print()
print('=== 주의 항목 ===')
for i in low: print(f'{i[\"name\"]}: 재고부족={i[\"is_low_stock\"]}, 임박={i[\"is_expiring\"]}, {i.get(\"days_left\")}일')
print()
print('=== 쇼핑리스트 ===')
for i in shopping: print(f'{i[\"name\"]} {i[\"quantity\"]}{i[\"unit\"]}')
\""
   ```

2. 결과를 아래 형식으로 정리해라:

---
**식재료 현황 — [날짜]**

**🔴 즉시 처리 필요** (유통기한 3일 이내)
- 재료명: X일 남음 → 활용 아이디어 한 줄

**🟡 재고 부족**
- 재료명: 현재 수량

**🛒 쇼핑리스트** (N개)
- 목록

**✅ 정상 재고** (N개)
---

3. 유통기한 임박 재료가 있으면 물어봐라: "임박 재료로 만들 수 있는 요리 추천해줄까요?"
   - "응" 하면: 임박 재료 조합으로 만들 수 있는 요리 2-3개 추천 (재료·조리 시간 포함)
