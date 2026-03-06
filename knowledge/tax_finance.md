# 세무/재무 지식 베이스
# Claude가 Planby 재무·세무 작업 시 참조하는 파일

## 수치 검증 원칙
- AnythingLLM 답변의 숫자는 **반드시 원본 문서와 교차 확인** 후 제시
- 재무 수치 오류 사례: 이월결손금 "121,000,000원" (실제: 483,518,578원) — PDF 임베딩 오류
- 중요 수치는 출처 명시: 원본 PDF/Excel > AnythingLLM 답변 > 추정치 순으로 신뢰
- 부재/미납 결론은 1차 원본 데이터(은행거래내역 등)로만 내릴 것

## Planby 접근 권한
- **회사 workspace (planby)**: 읽기 전용. 절대 쓰기 금지. COMPANY_NOTION_TOKEN은 조회만.
- Notion API: table_row 타입은 update-block 불가 → insert-after(table 블록 기준)로 우회

## 자주 쓰는 데이터 파일 위치
- 엑셀 파일: `~/Desktop/플랜바이 자료/플랜바이 재무:세무 정보/Clobe.AI 엑셀 파일/`
- PDF 변환: `soffice --headless --convert-to pdf --outdir <dir> <file>`
