
다음 Python 스크립트를 작성해주세요.

## 목적
Notion 페이지에 마크다운 파일을 배치로 append하는 자동화 스크립트.
notion_db.py의 append 커맨드를 활용합니다.

## notion_db.py append 사용법
python C:/Users/1/notion_db.py append [page_id] --content-file [filepath]

## 요구사항
1. 스크립트 파일: C:/Users/1/notion_batch_append.py
2. 입력: JSON 매핑 파일 경로 (인자로 받음)
3. JSON 매핑 파일 형식:
[
  {"page_id": "xxx", "file": "C:/Users/1/content_file.md", "label": "페이지명"},
  ...
]
4. 동작:
   - 매핑 파일을 순서대로 읽음
   - 각 항목에 대해 notion_db.py append 실행
   - 성공/실패 출력 (label 포함)
   - 실패 시 계속 진행 (중단하지 않음)
   - 완료 후 요약 출력 (성공 N개 / 실패 N개)
5. 실행 예시: python C:/Users/1/notion_batch_append.py C:/Users/1/batch_map.json
6. PYTHONIOENCODING=utf-8 환경 처리 포함

간결하게 작성하세요 (50줄 이내).

