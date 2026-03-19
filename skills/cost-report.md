플랜바이 월간 원가 분석 리포트를 실행한다.

## 실행 순서

### 1. 대상 월 확인

`$ARGUMENTS`가 있으면 그 달을 사용 (예: `2026-03`).
없으면 현재 날짜 기준 **직전 달**을 자동으로 사용.

### 2. 데이터 파일 최신 여부 안내

아래 3개 파일이 대상 월 데이터를 포함하는지 사용자에게 안내:
- `bank_2024_2026.xlsx`
- `card_2024_2026.xlsx`
- `invoices_2024_2026.xlsx`

파일 범위가 대상 월을 포함하지 않으면 Clobe.AI에서 재다운로드 후 M1에 복사 안내:
```bash
scp [다운로드경로]/bank_*.xlsx luma2@m1:~/projects/planby-tools/bank_2024_2026.xlsx
scp [다운로드경로]/card_*.xlsx luma2@m1:~/projects/planby-tools/card_2024_2026.xlsx
scp [다운로드경로]/invoices_*.xlsx luma2@m1:~/projects/planby-tools/invoices_2024_2026.xlsx
```

### 3. M1에서 분석 실행

```bash
ssh luma2@m1 "cd ~/projects/planby-tools && source .venv/bin/activate && \
  python cost_analyzer.py \
    --bank bank_2024_2026.xlsx \
    --card card_2024_2026.xlsx \
    --invoices invoices_2024_2026.xlsx \
    --rules rules.yaml \
    --month {대상월} \
    --output report_{대상월}.md \
    --thousand-unit \
    --role-counts 'developer=8,designer=2,pm=1,ceo=2,admin=1'"
```

### 4. 리포트 출력

```bash
ssh luma2@m1 "cat ~/projects/planby-tools/report_{대상월}.md"
```

내용을 그대로 사용자에게 출력.

### 5. 핵심 수치 요약

리포트에서 다음 항목을 추출해 표로 정리:
- 총매출 (천원)
- COGS (천원)
- Gross Margin (%)
- SGA (천원)
- 영업이익 (천원)
- 인건비 COGS 배부 / SGA 배부 (천원)

### 6. Notion 업데이트

`mcp__claude_ai_Notion__notion-update-page`로 해당 월 페이지 업데이트.

PAGE_IDS 매핑 (대상 월에 해당하는 page_id 사용):
- 2024-01: 3280ef18-d41a-818b-b24a-f26b9455c4ec
- 2024-02: 3280ef18-d41a-81a8-b5cc-dbbea0f7ea9b
- 2024-03: 3280ef18-d41a-8181-9b2e-e39afda2eb32
- 2024-04: 3280ef18-d41a-8193-a0f8-da32999c0e85
- 2024-05: 3280ef18-d41a-81fd-80b0-d4382fdb99ce
- 2024-06: 3280ef18-d41a-818c-9613-f0362e61a6be
- 2024-07: 3280ef18-d41a-8107-a652-e723158db737
- 2024-08: 3280ef18-d41a-818d-a7ea-ed8ab515f47c
- 2024-09: 3280ef18-d41a-81cd-a1ce-ec156e635dc7
- 2024-10: 3280ef18-d41a-8193-a963-f39154b3aa88
- 2024-11: 3280ef18-d41a-819c-8e73-d975a2680da1
- 2024-12: 3280ef18-d41a-8189-927f-fdb212b936db
- 2025-01: 3280ef18-d41a-8169-9e6d-f4cf1f651706
- 2025-02: 3280ef18-d41a-8154-b4fb-d75f0b923639
- 2025-03: 3280ef18-d41a-81a4-9f8b-e958cdbc7d42
- 2025-04: 3280ef18-d41a-8116-a313-d62869aa5671
- 2025-05: 3280ef18-d41a-812b-923a-f53c79cc7b4a
- 2025-06: 3280ef18-d41a-816f-97ee-da23ca4d8193
- 2025-07: 3280ef18-d41a-8163-bc3d-f45cfebd03bc
- 2025-08: 3280ef18-d41a-810b-9237-d4a398f16177
- 2025-09: 3280ef18-d41a-81b0-a915-f640fd9682b4
- 2025-10: 3280ef18-d41a-81e6-ac45-e7204b80f62a
- 2025-11: 3280ef18-d41a-811d-9ad0-d35eb51beddc
- 2025-12: 3280ef18-d41a-814c-a92d-f81542301535
- 2026-01: 3280ef18-d41a-814a-8ef8-d927c19c36ae
- 2026-02: 3280ef18-d41a-8134-8fce-c8cd6853b212
- 2026-03: 3280ef18-d41a-81ab-9e7b-f317654bdd94

업데이트할 properties:
```json
{
  "총매출": 숫자(원),
  "COGS": 숫자(원),
  "SGA": 숫자(원),
  "Gross Margin": 숫자(퍼센트, 예: 82.7),
  "영업이익": 숫자(원),
  "정부지원금": 숫자(원, 리포트 GRANT 합계. 없으면 0),
  "메모": "자동입력 via cost_analyzer {오늘날짜} (인건비배부 적용)"
}
```

신뢰도 판단 — 리포트에서 동적으로 파싱:
- 리포트에 `인건비(COGS배부)` 또는 `인건비(SGA배부)` 항목이 있고 값 > 0 → `🟢높음`
- 해당 항목이 없거나 0 → `🔴낮음` (급여 데이터 없는 달)

대상 월이 PAGE_IDS에 없으면 (신규 월):
1. `mcp__claude_ai_Notion__notion-create-pages`로 새 행 생성:
   - parent: `{"type": "data_source_id", "data_source_id": "bc59c156-fb33-4afc-903c-7ad0cd2860b9"}`
   - properties:
     ```json
     {
       "Name": "{대상월}",
       "date:월:start": "{대상월}-01",
       "date:월:is_datetime": 0
     }
     ```
2. 응답에서 `page_id` 추출
3. 위 업데이트할 properties + 신뢰도를 해당 page_id에 적용
4. **스킬 파일(`~/projects/agent-orchestration/skills/cost-report.md`)의 PAGE_IDS 목록에 새 항목 추가** (Edit 툴 사용):
   - `- 2026-03: 3280ef18-d41a-81ab-9e7b-f317654bdd94` 아래에 `- {대상월}: {새 page_id}` 삽입
5. `bash ~/projects/agent-orchestration/scripts/sync.sh` 실행으로 스킬 배포

### 7. 완료 메시지

```
✅ {대상월} 원가 분석 완료
- 총매출: XXX천원 | GM: XX.X% | 영업이익: XXX천원
- Notion 업데이트 완료
```
