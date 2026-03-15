# Codex Task Brief — 문서 생성 파이프라인 (docs pipeline)

## Goal
슬라이드 파이프라인(slides.sh)과 동일한 구조로 문서 자동 생성 파이프라인 구축.
`docs.sh "주제" [type]` → Gemini JSON → inject-docs.py → render-docs.sh → A4 PDF

## Context Budget
- 참조 파일: `scripts/slides.sh`, `scripts/inject-slides.py`, `scripts/render-slides.sh`
- 참조 디렉토리: `templates/slides/` (구조 참고용)
- 생성 디렉토리: `templates/docs/`, `scripts/`
- 건드리지 않는 파일: slides 관련 모든 파일

## Stop Triggers
- render-docs.sh 테스트 실패 시 STOP
- inject-docs.py --validate 실패 시 STOP
- A4 PDF에 내용이 잘리는 경우 STOP (overflow: hidden 금지)

---

## Files to Create

### 1. `templates/docs/base.html`
A4 문서용 공통 CSS.

```css
/* 색상 토큰 (slides와 동일) */
:root {
  --accent-1: #2563EB;
  --accent-dark: #1D4ED8;
  --text-primary: #111827;
  --text-secondary: #374151;
  --text-muted: #6B7280;
  --border: #E5E7EB;
  --bg-white: #FFFFFF;
  --bg-light: #F9FAFB;
}

/* A4 기본 설정 */
@page { size: A4; margin: 0; }
* { box-sizing: border-box; }
body { margin: 0; font-family: 'Noto Sans KR', sans-serif; background: #fff; }

/* 페이지 단위: .page 클래스 */
.page {
  width: 210mm;
  min-height: 297mm;
  padding: 20mm 22mm;
  position: relative;
  page-break-after: always;
}
.page:last-child { page-break-after: avoid; }

/* 공통 타이포그래피 */
h1 { font-size: 28px; font-weight: 800; color: var(--text-primary); margin: 0 0 8px; }
h2 { font-size: 20px; font-weight: 700; color: var(--text-primary); margin: 0 0 12px; border-bottom: 2px solid var(--accent-1); padding-bottom: 6px; }
h3 { font-size: 16px; font-weight: 700; color: var(--text-primary); margin: 0 0 8px; }
p  { font-size: 14px; line-height: 1.75; color: var(--text-secondary); margin: 0 0 12px; word-break: keep-all; }
```

---

### 2. 7개 컴포넌트 (`templates/docs/components/`)

각 파일은 `.page` div를 직접 출력. Jinja2 스타일 `{{ }}` 변수, `{% for %}...{% endfor %}` 반복 사용.

#### cover.html
표지 페이지 (한 페이지 전용, 세로 중앙 정렬)
```
data 키: title, subtitle, type_label, company, date
```
레이아웃:
- 상단 accent-1 띠 (height: 8px)
- 세로 중앙 정렬
  - type_label: 배지 (border accent-1, 파란 텍스트, 12px uppercase)
  - title: 36px bold
  - subtitle: 18px text-muted (있으면 표시, `:empty`면 숨김)
- 하단 푸터: company + " | " + date, text-muted 14px

#### section.html
일반 본문 섹션 (긴 텍스트, 자동 줄바꿈 허용)
```
data 키: heading, body
```
레이아웃:
- `<h2>` heading (상단 accent 언더라인)
- `<p>` body (14px, line-height 1.75, word-break: keep-all)
- 섹션 간 `margin-bottom: 32px`

#### bullet_section.html
불릿 리스트 섹션
```
data 키: heading, items (list of {title, desc} 또는 단순 string)
```
레이아웃:
- `<h2>` heading
- 각 item: 왼쪽 accent-1 원형 불릿(8px) + title bold + desc text-muted
- item이 string이면 desc 없이 title만 표시

#### table_section.html
표 섹션
```
data 키: heading, headers (list of string), rows (list of list)
```
레이아웃:
- `<h2>` heading
- `<table>`: 전체 너비, border-collapse: collapse
- `<thead>`: accent-1 배경, 흰 텍스트, 12px uppercase
- `<tbody>`: 홀수행 bg-light, 짝수행 white, 14px
- 셀 padding: 10px 14px, border: 1px solid var(--border)

#### highlight_box.html
핵심 메시지 강조 박스
```
data 키: label, text, sub_text (선택)
```
레이아웃:
- border-left: 4px solid var(--accent-1)
- background: #EFF6FF (accent-1의 10% 투명도)
- padding: 16px 20px
- label: 11px uppercase bold accent-1
- text: 18px bold text-primary
- sub_text: 13px text-muted (`:empty`면 숨김)

#### two_col.html
2컬럼 레이아웃
```
data 키: heading, left_heading, left_items (list of string), right_heading, right_items (list of string)
```
레이아웃:
- `<h2>` heading (전체 폭)
- 두 컬럼 flex, gap: 32px
- 각 컬럼: h3 + bullet list (accent-1 불릿)

#### closing.html
마무리 / 연락처
```
data 키: text, contact_name, contact_email, contact_phone (선택)
```
레이아웃:
- accent-1 배경, 흰 텍스트
- text: 20px bold 중앙 정렬
- 하단 연락처: name | email | phone (있는 것만 표시, `:empty`면 숨김)

---

### 3. `scripts/inject-docs.py`

inject-slides.py와 동일한 구조. 차이점:
- 경로: `REPO_ROOT / "templates" / "docs" / "base.html"`, `templates/docs/components/`
- 섹션 단위: `<div class="section">` (slides처럼 `.slide`가 아님)
- 컴포넌트들은 `.page` div를 직접 출력 (inject는 감싸지 않음)
- `--validate` 플래그 지원

JSON 스키마:
```json
{
  "meta": { "title": "문서 제목", "type": "proposal" },
  "sections": [
    { "type": "cover", "data": { "title": "...", "subtitle": "...", "type_label": "제안서", "company": "플랜바이", "date": "2026-03-15" } },
    { "type": "section", "data": { "heading": "...", "body": "..." } },
    { "type": "bullet_section", "data": { "heading": "...", "items": [{"title": "...", "desc": "..."}] } },
    { "type": "table_section", "data": { "heading": "...", "headers": ["항목", "내용"], "rows": [["...", "..."]] } },
    { "type": "highlight_box", "data": { "label": "핵심", "text": "...", "sub_text": "..." } },
    { "type": "two_col", "data": { "heading": "...", "left_heading": "...", "left_items": ["..."], "right_heading": "...", "right_items": ["..."] } },
    { "type": "closing", "data": { "text": "...", "contact_name": "...", "contact_email": "..." } }
  ]
}
```

validate_schema: sections 배열 검사, 각 type별 required 키 검사.

bullet_section preprocess: items 각 요소가 string이면 `{"title": item, "desc": ""}` 로 변환.

---

### 4. `scripts/render-docs.sh`

render-slides.sh와 거의 동일. 차이점:
- Playwright pdf() 옵션: `format: 'A4'` 사용 (width/height 대신)
- check-slides.sh 호출 제거 (문서용 CHK 없음)
- 사용법: `bash render-docs.sh <input.html> [output-name]`

```javascript
await page.pdf({
  path: '${PDF_PATH}',
  format: 'A4',
  printBackground: true,
  margin: { top: 0, right: 0, bottom: 0, left: 0 },
});
```

---

### 5. `scripts/docs.sh`

slides.sh와 동일한 구조.

```bash
# Usage: bash docs.sh "주제" [type=proposal] [--dry-run]
# type 선택: proposal | report | business_plan | summary | meeting
```

type별 Gemini 프롬프트 (각 type에 맞는 섹션 구조 가이드 포함):

**proposal (제안서)**:
- 권장 구조: cover → highlight_box(요약) → section(문제) → section(솔루션) → table_section(사양/가격) → two_col(장점 비교) → closing

**report (리포트)**:
- 권장 구조: cover → section(현황) → section(분석) → table_section(데이터) → bullet_section(시사점) → highlight_box(결론) → closing

**business_plan (사업계획서)**:
- 권장 구조: cover → highlight_box(한 줄 요약) → section(사업 개요) → section(시장 분석) → bullet_section(핵심 역량) → table_section(재무 계획) → closing

**summary (요약본)**:
- 권장 구조: cover → highlight_box(핵심 요약) → bullet_section(주요 내용) → section(결론) → closing

**meeting (회의록)**:
- 권장 구조: cover → table_section(참석자/안건) → bullet_section(논의 내용) → table_section(결정 사항 및 담당자) → section(다음 액션) → closing

공통 Gemini 프롬프트 규칙:
- 첫 섹션은 반드시 cover
- 마지막 섹션은 반드시 closing
- 모든 텍스트는 한국어
- section body는 3-5문장 분량
- JSON 외 다른 텍스트 출력 금지

---

## Test

테스트 JSON (`test_docs_proposal.json`) 직접 생성 후 실행:

```json
{
  "meta": { "title": "스마트 오피스 솔루션 제안서", "type": "proposal" },
  "sections": [
    { "type": "cover", "data": { "title": "스마트 오피스 솔루션 제안서", "subtitle": "공간 데이터 기반 업무 환경 혁신", "type_label": "제안서", "company": "플랜바이", "date": "2026-03-15" } },
    { "type": "highlight_box", "data": { "label": "핵심 제안", "text": "유휴 공간을 34% 줄이고 협업 효율을 2배 높입니다.", "sub_text": "6개월 내 ROI 달성, 데이터 기반 의사결정 지원" } },
    { "type": "section", "data": { "heading": "현재 문제", "body": "대부분의 기업은 전체 사무공간의 30-40%를 비효율적으로 사용하고 있습니다. 회의실 예약은 넘치지만 실제 사용률은 낮고, 직원들은 자리를 찾아 헤매며 시간을 낭비합니다. 공간 데이터가 없으면 어디서 낭비가 발생하는지 알 수 없습니다." } },
    { "type": "section", "data": { "heading": "플랜바이 솔루션", "body": "플랜바이는 IoT 센서와 AI 분석을 결합해 실시간 공간 사용 데이터를 수집·분석합니다. 좌석 예약, 회의실 관리, 유동 인구 분석을 하나의 플랫폼에서 제공하며 대시보드를 통해 관리자가 즉시 의사결정을 내릴 수 있습니다." } },
    { "type": "table_section", "data": { "heading": "도입 플랜", "headers": ["구분", "Basic", "Pro", "Enterprise"], "rows": [["센서 수", "최대 50개", "최대 200개", "무제한"], ["대시보드", "기본", "고급", "맞춤형"], ["월 비용", "150만원", "350만원", "협의"]] } },
    { "type": "two_col", "data": { "heading": "도입 효과", "left_heading": "정량적 효과", "left_items": ["유휴 공간 34% 감소", "회의실 예약률 2.1배 향상", "에너지 비용 18% 절감"], "right_heading": "정성적 효과", "right_items": ["직원 만족도 향상", "데이터 기반 공간 의사결정", "하이브리드 근무 최적화"] } },
    { "type": "closing", "data": { "text": "플랜바이와 함께 스마트한 공간을 만들어보세요.", "contact_name": "플랜바이 영업팀", "contact_email": "hello@planby.io", "contact_phone": "" } }
  ]
}
```

실행:
```bash
python3 inject-docs.py test_docs_proposal.json --out /c/Users/1/AppData/Local/Temp/test-docs.html
bash render-docs.sh /c/Users/1/AppData/Local/Temp/test-docs.html "test-docs-proposal"
```

PDF `~/Desktop/test-docs-proposal.pdf` 생성 확인.

## Done Criteria
- [ ] `templates/docs/base.html` 생성
- [ ] 7개 컴포넌트 HTML 생성
- [ ] `inject-docs.py` 동작 (--validate 통과)
- [ ] `render-docs.sh` 생성
- [ ] `docs.sh` 생성 (5개 type 지원, --dry-run 포함)
- [ ] 테스트 PDF 생성 성공 (A4, 레이아웃 정상)
