# 태스크: 독서허브 에세이 41개 Notion 페이지 재구성 스크립트

## 목표
Python 스크립트 1개 (`C:/Users/1/rebuild_essay_pages.py`) 를 작성한다.
스크립트는 Notion API를 직접 호출해 에세이 41개 페이지의 기존 블록을 전부 삭제하고 새 구조로 재작성한다.

## 환경
- Python 3, 표준 라이브러리만 사용 (requests 없음, urllib 사용)
- TOKEN = os.getenv("PERSONAL_NOTION_TOKEN") or os.getenv("NOTION_TOKEN")
- Notion-Version: "2022-06-28"
- Windows 환경 → 이모지는 반드시 Unicode escape 사용 (\U0001f4da 등), 인라인 이모지 금지

## 새 페이지 구조 (8섹션, 각 페이지 공통)
```
## 1) 추천 에세이·수기   ← numbered list 3권: "제목 — 저자 (선택 이유)"
## 2) 이 직업을 한 마디로  ← paragraph 1~2문장
## 3) 실제 하루           ← h3: 루틴 / 피크타임 / 소모 포인트 각 bullet 2~3개
## 4) 애환과 보람         ← h3 4개 (가장 힘든 순간 / 가장 보람된 순간 / 외부인이 모르는 현실 / 반복되는 딜레마) 각 bullet 2개
## 5) 구조적 현실         ← h3: 경력경로 / 노동강도 / 제도·시장 각 bullet 2개
## 6) 읽은 후 내 생각     ← callout(이모지=\u270f\ufe0f): "이 책을 읽고 나서 직접 채우기"
## 7) 인상 깊은 구절·장면 ← quote: "직접 채우기"
## 8) 다음               ← to_do 2개: 읽을 책 / 비교해볼 직업
```

## 블록 빌더 함수 (스크립트 내 정의)
```python
def h2(text): ...
def h3(text): ...
def p(text): ...
def b(text): ...  # bulleted_list_item
def n(text): ...  # numbered_list_item
def quote(text): ...
def callout(text, emoji="\u270f\ufe0f"): ...
def todo(text): ...
def div(): ...
```

## 페이지 처리 로직
```python
def rebuild_page(page_id, job_name, blocks):
    # 1. GET /blocks/{page_id}/children (페이지네이션 포함)
    # 2. DELETE 각 child block (child_page 타입 제외 — 보호)
    # 3. PATCH /blocks/{page_id}/children 새 블록 append (100개씩 배치)
    # rate limit: delete 후 0.15초, append 후 0.3초 sleep
```

## 직업별 콘텐츠 데이터 (JOBS dict)
각 직업에 대해 아래 키를 채울 것:
- books: list of 3 tuples (제목, 저자, 선택이유) — 1인칭 수기/에세이 우선, 실제 출판된 도서
- tagline: str (1~2문장)
- routine: list[str] (2~3개)
- peak: list[str] (2개)
- drain: list[str] (2개)
- hardest: list[str] (2개)
- rewarding: list[str] (2개)
- reality: list[str] (2개)
- dilemma: list[str] (1~2개)
- career: list[str] (2개)
- intensity: list[str] (2개)
- system: list[str] (2개)
- next_books: list[str] (2개 도서 제목)
- compare_jobs: list[str] (2개 직업명)

## 41개 직업 목록 및 페이지 ID
```python
JOBS = {
    "의사":        "30985046-ff55-810f-8f47-ecb4f3ac2a33",
    "주부":        "30985046-ff55-81b8-bc52-f67bb3f25efa",
    "변호사":      "30985046-ff55-8197-9e31-fb458e3c49d7",
    "회계사":      "30985046-ff55-81f8-9b5b-f453a07afdaa",
    "치과의사":    "30985046-ff55-8143-8a1d-d3f92995b3ac",
    "간호사":      "30985046-ff55-81a5-a1bc-d7e12c80befe",
    "건설노동자":  "30985046-ff55-819c-abf6-e59d3cb6be6b",
    "요리사":      "30985046-ff55-8189-918c-ce31520e710f",
    "가수":        "30985046-ff55-81a7-90cb-e209b754ad09",
    "배우":        "30985046-ff55-8187-815d-c0a7a2e5471d",
    "운동선수":    "30985046-ff55-81e5-ac2b-c72f811b1f67",
    "교사":        "30985046-ff55-815b-afc6-d0af81f971de",
    "소방관":      "30985046-ff55-8163-acb5-cf84b007577c",
    "경찰관":      "30985046-ff55-8141-aeb0-d2d0aab89f23",
    "약사":        "30985046-ff55-8113-8870-f290eae4f913",
    "물리치료사":  "30985046-ff55-81c8-88db-d30e33b2f614",
    "사회복지사":  "30985046-ff55-81cf-8297-c8a76d117fd2",
    "심리상담사":  "30985046-ff55-817a-a9f3-c35bc0f6345f",
    "소프트웨어 엔지니어": "30985046-ff55-81b8-bf62-e92e3f3b3122",
    "데이터 과학자":      "30985046-ff55-81a4-b32c-f9817b7e3735",
    "UX 디자이너":        "30985046-ff55-8126-8f35-dff96edf5e84",
    "게임 개발자":        "30985046-ff55-8195-9d5c-f959dd042a54",
    "기자":        "30985046-ff55-818d-86b1-de114aed6e8a",
    "사진작가":    "30985046-ff55-8116-8340-de74e9c2a5d6",
    "번역가":      "30985046-ff55-81a4-8fcb-ef038a0bd3dc",
    "농부":        "30985046-ff55-81e8-b069-d42c68f28437",
    "어부":        "30985046-ff55-81bd-a14e-fbd1aec34bb0",
    "항공기 조종사": "30985046-ff55-8102-8059-cc39c7048d30",
    "승무원":      "30985046-ff55-819d-8447-ed6aa12ed1af",
    "환경컨설턴트": "30985046-ff55-8129-b205-cd39c8298ce2",
    "물류관리자":  "30985046-ff55-81cd-83c4-c12f8776cc8e",
    "유튜버":      "30b85046-ff55-8197-a408-ebca788c890c",
    "CEO":         "30b85046-ff55-8115-bb2f-eb9bedaea092",
    "재무(FP&A/IR)": "30b85046-ff55-812d-882c-f8f4f03f07a0",
    "회계":        "30b85046-ff55-81d8-a616-d740fb2c5de6",
    "세무":        "30b85046-ff55-810e-b5ef-f1a3125297b4",
    "전략/기획":   "30b85046-ff55-8189-999c-c38e47387c0e",
    "인사(HR)":    "30b85046-ff55-8179-8c64-d96ec482b0ea",
    "영업/마케팅": "30b85046-ff55-81b3-adda-f150911264e1",
    "생산/공급망(SCM)": "30b85046-ff55-8168-94e9-f5369ca2518e",
    "법무/컴플라이언스": "30b85046-ff55-81d0-bf69-d5148bdd2218",
}
```

## 추천 도서 가이드라인
- 1인칭 수기/에세이 우선 (직접 쓴 책)
- 실제 한국에서 구할 수 있는 도서
- 직업과 직접 연관된 내용
- 소방관: 이길수 소방관 수기류, 불꽃 속으로 등 (골든아워1은 의사 책이므로 사용 금지)
- 어부: 바다 관련 어부 수기 (완벽한 폭풍은 미국 어부 책이므로 가능하나 맥락 설명 필요)
- 의사: 아픔이 길이 되려면(김승섭), 닥터의 일기(남궁인) 적극 활용

## Done Criteria
1. `C:/Users/1/rebuild_essay_pages.py` 파일 생성 완료
2. 실행 시 41개 페이지 순서대로 처리, 진행상황 print
3. child_page 타입 블록은 삭제하지 않고 보호
4. 에러 발생 시 해당 직업 스킵하고 계속 진행
5. 완료 후 "성공 N / 실패 N" 출력
