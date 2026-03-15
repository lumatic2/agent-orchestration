# Task Brief: content-automation HTML Slides + 2-Stage Pipeline

## Agent
Codex

## Goal
1. `video_creator.py`를 HTML+Playwright 방식으로 전면 재작성
2. `main.py`에 2단계 파이프라인 추가 (`--script-only` / `--from-content`)
3. `requirements.txt` 업데이트

## Working Directory
`C:\Users\1\Desktop\content-automation\`

## Scope (수정 대상 파일)
- `video_creator.py` — HTML+Playwright 방식으로 재작성
- `main.py` — 2단계 파이프라인 추가
- `requirements.txt` — playwright 추가
- `templates/slide.html` — 신규 (슬라이드 HTML 템플릿)

## 수정하지 말 것
- `generator.py`, `publisher.py`, `approver.py`, `blog_generator.py`, `common.py`, `config.yaml`

---

## 1. video_creator.py 재작성

### 핵심 방식
- 각 슬라이드를 HTML/CSS로 렌더링 → Playwright로 PNG 캡처 → MoviePy로 합성
- `playwright` Python 패키지 사용 (`playwright install chromium` 필요)

### 슬라이드 디자인 시스템 (config.yaml의 design 섹션 참고)
```
배경: #fafafa
텍스트: #1a1a1a
포인트 색: #1978e5
뮤트 텍스트: #737373
폰트: Malgun Gothic (Windows 시스템 폰트)
해상도: 1920×1080
```

### 슬라이드 타입
1. **title** — 제목 슬라이드
   - 상단 파란 바 (8px)
   - 중앙에 큰 타이틀 텍스트 (bold, 80px)
   - 하단 중앙에 파란 구분선 (가로 60%)
   - 우측 하단 "루마" 워터마크 (작은 글씨, #e5e5e5)

2. **point** — 본문 포인트 슬라이드
   - 상단 파란 바 (8px)
   - 좌측 파란 번호 뱃지 (원형, 흰 숫자)
   - 번호 오른쪽에 헤딩 텍스트 (bold, 56px)
   - 헤딩 아래 본문 텍스트 (regular, 36px, #737373)
   - 우측 하단 "루마" 워터마크

3. **end** — 마무리 슬라이드
   - 상단 파란 바 (8px)
   - 중앙 "구독 · 좋아요 · 알림설정" 텍스트
   - 하단 해시태그
   - 우측 하단 "루마" 워터마크

### HTML 렌더링 방식
```python
from playwright.sync_api import sync_playwright

def render_slide_to_png(html_content: str, output_path: str, width=1920, height=1080):
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": width, "height": height})
        page.set_content(html_content)
        page.screenshot(path=output_path, full_page=False)
        browser.close()
```

### 슬라이드 전환
- MoviePy `concatenate_videoclips` + `crossfadein`/`crossfadeout` (기존 방식 유지)
- 전환 시간: 0.4s (config.yaml `transition_duration`)
- 슬라이드 기본 지속 시간: 5s (오디오 없을 때), 오디오 있으면 audio_duration / slide_count

### 오디오 처리
- `audio_path`가 있으면 Whisper로 word-level timestamps 추출 → 카라오케 자막 오버레이
- `audio_path`가 없으면 무음으로 생성 (나중에 사람이 녹음 후 재생성)

### `create_video` 함수 시그니처 유지
```python
def create_video(content: dict[str, Any], output_path: str, config: dict[str, Any] | None = None) -> str:
```
`content` 구조:
```json
{
  "title": "영상 제목",
  "sections": [
    {"heading": "헤딩", "body": "본문 텍스트"},
    ...
  ],
  "audio_path": null
}
```

---

## 2. main.py 2단계 파이프라인

### 1단계: `--script-only`
```bash
python main.py --topic "AI 자동화" --script-only
```
- Gemini로 콘텐츠 생성
- `outputs/{stamp}_{topic}_content.json` 저장
- 텔레그램으로 스크립트 전달:
  ```
  📋 스크립트 준비됨
  주제: {topic}
  제목: {title}

  [스크립트]
  {script 전문}

  녹음 후 --from-content {json_path} --audio {audio_path} 로 실행하세요.
  ```

### 2단계: `--from-content`
```bash
python main.py --from-content outputs/xxx_content.json --audio recording.mp3
```
- 저장된 JSON에서 콘텐츠 로드 (Gemini 재호출 없음)
- 영상 + 썸네일 생성
- 텔레그램 승인 요청 (썸네일 이미지 포함)
- 승인 시 YouTube 업로드
- 블로그 초안 생성 → Vault

### 기존 `--topic` 단독 실행 (오디오 없이 전체 파이프라인)은 유지
```bash
python main.py --topic "AI 자동화"  # 기존 방식 그대로 동작
```

### `main.py`에 추가할 인자
```python
parser.add_argument("--script-only", action="store_true")
parser.add_argument("--from-content", type=str, default=None, help="저장된 content JSON 경로")
```

### 텔레그램 스크립트 전달 함수
`main.py` 내부에 `_send_script_to_telegram(content, config, json_path)` 추가:
- config에서 bot_token, chat_id 읽어서 sendMessage 호출
- 미설정 시 콘솔 출력으로 fallback

---

## 3. requirements.txt 업데이트
```
python-dotenv>=1.0.1
PyYAML>=6.0.1
requests>=2.32.3
google-api-python-client>=2.161.0
google-auth-oauthlib>=1.2.1
google-genai
moviepy>=1.0.3
openai-whisper
playwright>=1.40.0
```

---

## Done Criteria
1. `pip install playwright && playwright install chromium` 후 실행 가능
2. `python main.py --topic "테스트" --script-only` → outputs/에 JSON 저장 + 텔레그램 알림
3. `python main.py --from-content outputs/xxx.json` → 영상+썸네일 생성 (오디오 없이)
4. `python main.py --from-content outputs/xxx.json --audio test.mp3` → 오디오 포함 영상 생성
5. 슬라이드가 HTML 방식으로 렌더링됨 (PNG 임시 파일 생성 확인)
6. 기존 `python main.py --topic "주제"` 방식도 그대로 동작

## Notes
- Playwright 브라우저는 매 슬라이드마다 재시작하지 말고 browser 인스턴스를 재사용할 것
- 임시 PNG 파일은 `outputs/tmp/` 에 저장 후 영상 완성 시 삭제
- whisper import 실패 시 (미설치) 카라오케 자막 없이 진행 (기존 방식 유지)
