# Codex Task Brief — Slides Pipeline Option B

## Goal
슬라이드 생성 파이프라인을 "고정 HTML 템플릿 + JSON 콘텐츠 주입" 방식으로 재구축.
Gemini는 JSON만 생성 → inject-slides.py가 HTML 조립 → render-slides.sh로 PDF 렌더.

## Context Budget
- 집중 영역: `C:/Users/1/Desktop/agent-orchestration/`
- 읽어야 할 파일: `slides_config.yaml` (색상 토큰·기존 슬라이드 타입 참조용)
- 건드리지 않는 파일: `scripts/render-slides.sh`, `scripts/check-slides.sh`

## Stop Triggers
- render-slides.sh를 수정하기 시작하면 STOP
- 신규 색상 팔레트를 발명하면 STOP (slides_config.yaml의 토큰만 사용)
- 테스트 슬라이드 렌더 실패 시 STOP (경로 문제 등)

## Files to Create

### 1. `templates/slides/base.html`
공통 CSS만 포함하는 베이스 시트. 개별 컴포넌트는 이 CSS 변수를 재사용.

```css
/* 색상 토큰 (slides_config.yaml 기준) */
:root {
  --accent-1: #2563EB;
  --accent-dark: #1D4ED8;
  --text-primary: #111827;
  --text-secondary: #374151;
  --text-muted: #6B7280;
  --border: #E5E7EB;
  --bg-white: #FFFFFF;
  --bg-light: #F9FAFB;
  --bg-dark: #0F172A;
}
/* 슬라이드 기본 크기: 1280×720px */
.slide { width: 1280px; height: 720px; position: relative; overflow: hidden; box-sizing: border-box; }
/* 공통 폰트: Noto Sans KR + sans-serif fallback */
```

### 2. 8개 컴포넌트 파일 (`templates/slides/components/`)

각 파일은 `{TYPE}.html` 이름. Jinja2 스타일 변수(`{{ }}`) 사용.
inject-slides.py가 json 데이터로 치환.

#### title_panel.html
좌측 파란 패널(35%) + 우측 흰 배경
```
data 키: title, subtitle, points (list, 최대 4개)
```
레이아웃:
- 좌측 panel: bg=var(--accent-1), white text, 세로 중앙 정렬
- title: 40px bold
- subtitle: 16px #BBDEFB
- 우측: 아이콘 리스트 (points, 각 항목 앞 ✓ 또는 • 원)

#### card_grid.html
풀 화이트 배경 + 카드 그리드
```
data 키: badge, title, cards (list of {icon, title, desc}, 최대 6개)
```
레이아웃:
- 좌상단 badge: border 1.5px solid var(--accent-1), 파란 텍스트
- 제목: 28px bold
- 카드: flexbox wrap, 각 카드 = 아이콘(32px) + 제목 + 설명, border var(--border), border-radius 8px

#### numbered_list.html
좌 핵심 콘텐츠 + 구분선 + 우 번호 리스트
```
data 키: badge, title, subtitle, items (list of {num, title, desc}, 최대 4개)
```
레이아웃:
- 좌측(55%): badge + 큰 제목(32px) + 서브타이틀
- 구분선: 1px solid var(--border) 세로
- 우측(45%): 번호(01/02/03 형식, var(--accent-1) 색) + 제목 + 설명

#### bar_chart.html
좌 바 차트 + 우측 파란 accent 패널(28%)
```
data 키: badge, title, bars (list of {label, value, max}), hero_number, hero_label, sub_stats (list of {label, value})
```
레이아웃:
- 좌측(72%): 수평 막대 차트 (width % = value/max*100), 라벨 + 값
- 우측(28%): bg=var(--accent-1), hero 숫자(80px bold white) + hero_label + sub_stats

#### big_statement.html
화이트 배경 + 3색 타이포 계층
```
data 키: badge, line1, line2, line3
```
레이아웃:
- 좌상단: — 라인 + badge
- 중앙 세로 배치:
  - line1: 52px, var(--text-primary)
  - line2: 52px bold, var(--accent-1)
  - line3: 52px, var(--text-muted)

#### comparison_table.html
2컬럼 비교 테이블
```
data 키: badge, title, left_label, right_label, rows (list of {aspect, left, right, highlight: "left"|"right"|null})
```
레이아웃:
- 헤더: left_label(흰 배경) / right_label(var(--accent-1) bg, 흰 텍스트)
- 각 행: aspect 열(회색) + left + right
- highlight 있으면 해당 셀에 var(--accent-1) 텍스트 + bold

#### timeline.html
세로 타임라인
```
data 키: badge, title, steps (list of {year, title, desc}, 최대 5개)
```
레이아웃:
- 좌측 세로선(var(--accent-1))에 원형 노드 연결
- year: var(--accent-1) bold
- title: 굵은 텍스트
- desc: var(--text-muted)

#### quote_close.html
풀 파란 배경 + 인용구 (마무리 슬라이드)
```
data 키: quote, author, cta (선택)
```
레이아웃:
- bg: var(--accent-1), 전체 흰 텍스트
- SVG 큰따옴표 장식 (좌상단)
- 중앙 인용문: 36px, line-height 1.5
- author: 18px, 반투명
- cta 있으면 하단 흰 배지

### 3. `scripts/inject-slides.py`

```python
#!/usr/bin/env python3
"""
inject-slides.py — JSON 슬라이드 데이터 → 완성 HTML 조립

사용법:
  python3 inject-slides.py <slides.json> [--out /tmp/output.html]
  python3 inject-slides.py --validate <slides.json>   # JSON 유효성만 검사

출력:
  --out 지정 시 파일 저장, 없으면 stdout
"""
```

구현 요구사항:
1. `slides.json` 읽기 (schema 아래 참조)
2. `templates/slides/base.html` CSS 로드
3. 각 slide의 `type` 필드로 `templates/slides/components/{type}.html` 로드
4. `{{ key }}` 패턴을 `data` dict로 치환 (재귀 dict는 JSON 직렬화 후 치환)
5. 리스트 반복: `{% for item in cards %}...{% endfor %}` 패턴 지원
6. 조립된 슬라이드들을 `<div class="slide">` 단위로 연결, base CSS 포함한 완성 HTML 출력
7. `--validate` 플래그: JSON schema 검증만 하고 오류 목록 출력 후 종료
8. 오류 시 명확한 에러 메시지 (어느 슬라이드 몇 번째, 어느 키 누락)

### 4. `scripts/slides.sh`

```bash
#!/usr/bin/env bash
# slides.sh — Option B 슬라이드 생성 진입점
# Usage: bash slides.sh "주제" [슬라이드수=9] [--dry-run]
```

플로우:
1. `orchestrate.sh gemini` 호출 → Gemini에게 JSON 생성 요청
2. Gemini 출력에서 JSON 블록 추출 (`python3 -c "..."`)
3. `inject-slides.py slides.json --out /tmp/{slug}.html`
4. `render-slides.sh /tmp/{slug}.html "{slug}"`
5. `--dry-run` 지원

Gemini 프롬프트 (slides.sh 내에 변수로 포함):
```
주제: {TOPIC}
슬라이드 수: {SLIDE_N}

다음 JSON 스키마로 슬라이드 데이터를 생성해라. HTML 없이 JSON만 출력.

스키마:
{
  "meta": { "title": "슬라이드 제목" },
  "slides": [
    { "type": "title_panel", "data": { "title": "...", "subtitle": "...", "points": ["..."] } },
    { "type": "card_grid", "data": { "badge": "섹션명", "title": "...", "cards": [{"icon": "🎯", "title": "...", "desc": "..."}] } },
    { "type": "numbered_list", "data": { "badge": "...", "title": "...", "subtitle": "...", "items": [{"num": "01", "title": "...", "desc": "..."}] } },
    { "type": "bar_chart", "data": { "badge": "...", "title": "...", "bars": [{"label": "...", "value": 85, "max": 100}], "hero_number": "85%", "hero_label": "...", "sub_stats": [{"label": "...", "value": "..."}] } },
    { "type": "big_statement", "data": { "badge": "...", "line1": "...", "line2": "...", "line3": "..." } },
    { "type": "comparison_table", "data": { "badge": "...", "title": "...", "left_label": "...", "right_label": "...", "rows": [{"aspect": "...", "left": "...", "right": "...", "highlight": null}] } },
    { "type": "timeline", "data": { "badge": "...", "title": "...", "steps": [{"year": "2020", "title": "...", "desc": "..."}] } },
    { "type": "quote_close", "data": { "quote": "...", "author": "...", "cta": "..."} }
  ]
}

규칙:
- 첫 슬라이드는 반드시 title_panel
- 마지막 슬라이드는 반드시 quote_close
- 중간 슬라이드는 주제에 맞게 타입 선택 (같은 타입 3회 이상 연속 금지)
- 모든 텍스트는 한국어
- JSON 외 다른 텍스트 출력 금지
```

## Files to Deprecate (이동, 삭제 아님)
다음 파일들을 `scripts/_deprecated/` 디렉토리로 이동:
- `scripts/slides-bridge.sh`
- `scripts/gws-slides.sh`
- `scripts/gen-brief.sh`
- `blueprints/slides.yaml`

## Test
구현 완료 후 테스트 슬라이드 생성:
```bash
python3 inject-slides.py test_slides.json --out /tmp/test-slides.html
```

`test_slides.json` 내용 (직접 생성):
```json
{
  "meta": { "title": "Option B 테스트" },
  "slides": [
    { "type": "title_panel", "data": { "title": "Option B 슬라이드 시스템", "subtitle": "고정 템플릿 + JSON 주입", "points": ["일정한 품질", "Gemini JSON만 생성", "HTML 직접 생성 없음"] } },
    { "type": "big_statement", "data": { "badge": "핵심 원칙", "line1": "템플릿은", "line2": "한 번만 만든다", "line3": "콘텐츠만 바꾼다" } },
    { "type": "quote_close", "data": { "quote": "품질은 시스템에서 나온다.", "author": "Option B 테스트", "cta": "슬라이드 생성 완료" } }
  ]
}
```

HTML 렌더 확인 후 `bash render-slides.sh /tmp/test-slides.html "option-b-test"` 실행.
PDF `~/Desktop/option-b-test.pdf` 생성 확인.

## Done Criteria
- [ ] `templates/slides/base.html` 생성
- [ ] 8개 컴포넌트 HTML 생성
- [ ] `inject-slides.py` 동작 (test_slides.json → HTML 정상 출력)
- [ ] `slides.sh` 생성 (--dry-run 출력 확인)
- [ ] deprecated 파일 4개 → `scripts/_deprecated/` 이동
- [ ] 테스트 PDF 생성 성공 (render-slides.sh 통과)
