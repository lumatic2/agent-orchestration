# Task Brief: content-automation 파이프라인 전면 재구성

## Goal
`C:\Users\1\Desktop\content-automation\` 프로젝트를
"슬라이드 + 직접 녹음 음성 + 카라오케 자막" 유튜브 영상 자동 생성 파이프라인으로 재구성.

## 채널 디자인 시스템 (절대 변경 금지)
```
BG:           #fafafa  (흰 배경)
TEXT:         #1a1a1a  (기본 텍스트)
TEXT_MUTED:   #737373  (보조 텍스트)
BLUE:         #1978e5  (포인트 컬러 — 강조, 아이콘, 하단 바)
BLUE_LIGHT:   #EFF6FF  (포인트 배경)
BORDER:       #e5e5e5  (구분선)
```

## Scope (수정/생성 대상 파일)

### 1. `video_creator.py` — 전면 재작성
**입력:**
```python
content = {
    "title": str,           # 영상 제목
    "sections": [           # 슬라이드 목록
        {"heading": str, "body": str},  # 각 슬라이드
        ...
    ],
    "audio_path": str,      # 직접 녹음한 MP3/WAV 파일 경로 (없으면 None)
}
output_path = "outputs/video.mp4"
```

**처리 흐름:**
1. `audio_path` 있으면 Whisper로 word-level timestamp 추출
   - `whisper.load_model("base")` + `word_timestamps=True`
   - sections 수만큼 오디오를 균등 분할 → 각 슬라이드 duration 결정
2. Pillow로 슬라이드 이미지 생성 (1920×1080)
   - 레이아웃: 흰 배경, 상단 파란 강조바(8px, #1978e5), 중앙 텍스트
   - 타이틀 슬라이드: 큰 제목(80px bold) + 파란 하단 라인
   - 콘텐츠 슬라이드: heading(60px bold, #1a1a1a) + body(38px, #737373)
   - 우하단 워터마크: "루마" 텍스트 (24px, #e5e5e5)
   - 폰트: C:/Windows/Fonts/malgunbd.ttf (bold), malgun.ttf (regular)
3. MoviePy로 영상 합성
   - 각 슬라이드 ImageClip duration = 해당 오디오 구간 길이
   - audio_path 없으면 슬라이드당 5초 고정
   - crossfadein(0.4) / crossfadeout(0.4) 전환
   - `concatenate_videoclips(clips, padding=-0.4, method="compose")`
4. 카라오케 자막 오버레이 (audio_path 있을 때만)
   - Whisper segments → 3~5단어씩 묶어서 TextClip 생성
   - 위치: 하단 중앙, 화면 하단 80px 위
   - 스타일: 흰 텍스트(42px, bold) + 반투명 검정 박스(opacity 0.7)
   - 폰트: malgunbd.ttf
5. `video.write_videofile(output_path, fps=30, codec="libx264", audio=True)`

**오디오 없을 때:** 슬라이드 5초 고정, 자막 없음, 무음 영상 출력

### 2. `thumbnail.py` — 신규 생성
**입력:**
```python
def create_thumbnail(title: str, subtitle: str = "", output_path: str = "thumbnail.png") -> str
```
**스펙:**
- 크기: 1280×720
- 배경: #fafafa
- 상단 좌측: "루마" 브랜드 텍스트 (28px, #1978e5, bold)
- 메인 타이틀: 화면 중앙 상단, 최대 2줄, 72px bold, #1a1a1a
- 서브타이틀: 타이틀 아래, 40px, #737373
- 우측 하단: 파란 원형 배지 (지름 120px, #1978e5) + 흰 텍스트
- 하단 파란 강조바: 전체 폭, 12px, #1978e5
- `assets/luma_character.png` 존재하면 우측에 배치 (없으면 스킵)

### 3. `blog_generator.py` — 신규 생성
**입력:**
```python
def generate_blog_post(topic: str, content: dict, vault_base: str = None) -> str
```
**처리 흐름:**
1. Gemini Flash로 블로그 글 생성 (800~1200자, 한국어)
   - `GEMINI_API_KEY` from env
   - 포맷: 마크다운 (제목, 소제목, 본문, 마무리)
2. 파일 저장
   - 기본 경로: SSH로 M1 vault에 저장
   - 폴백: `outputs/blog_YYYYMMDD_topic.md`
3. 텔레그램 알림 발송
   - `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` from config
   - 메시지: "📝 블로그 초안 완성\n주제: {topic}\n파일: {path}\n\n네이버 블로그에 직접 포스팅해주세요."
4. 파일 경로 반환

### 4. `main.py` — 신규 생성 (통합 진입점)
```bash
# Type A: 정보전달형 (대본 자동생성 + 슬라이드 영상)
python main.py --topic "AI 자동화" --audio recordings/narration.mp3

# Type B: 음성만 있을 때 (나중에 확장)
python main.py --topic "AI 자동화"  # 오디오 없이도 실행 가능

# 블로그만
python main.py --blog --topic "네이버 블로그 주제"

# 드라이런
python main.py --topic "테스트" --dry-run
```

**흐름:**
1. `generator.py`로 콘텐츠 생성 (topic → title + sections + hashtags)
2. `video_creator.py`로 영상 생성
3. `thumbnail.py`로 썸네일 생성
4. `publisher.py`로 YouTube 업로드 (dry-run이면 스킵)
5. `blog_generator.py`로 블로그 초안 생성 + 텔레그램 알림

### 5. `config.yaml` — 업데이트
추가:
```yaml
design:
  bg: "#fafafa"
  text: "#1a1a1a"
  text_muted: "#737373"
  blue: "#1978e5"
  blue_light: "#EFF6FF"
  border: "#e5e5e5"
  font_bold: "C:/Windows/Fonts/malgunbd.ttf"
  font_regular: "C:/Windows/Fonts/malgun.ttf"
  character_path: "assets/luma_character.png"

video:
  width: 1920
  height: 1080
  fps: 30
  slide_default_duration: 5
  transition_duration: 0.4
  subtitle_font_size: 42
  whisper_model: "base"

thumbnail:
  width: 1280
  height: 720
  brand_name: "루마"
```

## 변경 금지 파일
- `generator.py` (내용 수정 없이 import만 사용)
- `publisher.py` (내용 수정 없이 import만 사용)
- `approver.py`, `scheduler.py`, `common.py`
- `credentials/` 폴더

## Dependencies 추가 (requirements.txt에 추가)
```
openai-whisper
```
(moviepy, pillow은 이미 있음)

## Done Criteria
1. `python main.py --topic "AI 자동화" --dry-run` 오류 없이 실행
2. `python main.py --topic "AI 자동화"` → outputs/ 에 MP4 + PNG 생성
3. `python main.py --blog --topic "테스트"` → MD 파일 생성 + 텔레그램 알림
4. `python video_creator.py --test` → 기존 테스트도 통과

## Notes
- Windows 환경 (C:/Windows/Fonts/)
- Python 3.10
- Whisper 모델은 "base" (속도/정확도 균형)
- 캐릭터 파일(luma_character.png) 없으면 gracefully skip
- 모든 한국어 텍스트 처리 시 UTF-8 명시
