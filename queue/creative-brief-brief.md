# Creative Brief Bot 구현

## 목표
매일 아침 Telegram으로 Sora/Midjourney/Suno/Kling 사용 프롬프트를 자동 생성해서 전송하는 봇.

## 만들 파일

### 1. scripts/creative-brief.py
Gemini API로 오늘의 테마 기반 프롬프트 생성 → Telegram 전송.

```python
#!/usr/bin/env python3
"""AI Creative Brief Bot — 매일 Sora/Midjourney/Suno/Kling 프롬프트 자동 생성"""
import os
import sys
import json
import urllib.request
from datetime import datetime

# ── 환경변수 (secrets_load.sh에서 주입됨) ──
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
TELEGRAM_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")

DRY_RUN = "--dry-run" in sys.argv

def gemini_generate(prompt: str) -> str:
    """Gemini 2.5 Flash API 직접 호출"""
    if not GEMINI_API_KEY:
        raise RuntimeError("GEMINI_API_KEY 미설정")
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={GEMINI_API_KEY}"
    body = json.dumps({"contents": [{"parts": [{"text": prompt}]}]}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read())
    return data["candidates"][0]["content"]["parts"][0]["text"]

def telegram_send(message: str) -> bool:
    if not TELEGRAM_TOKEN or not TELEGRAM_CHAT_ID:
        print("[WARN] Telegram 미설정")
        return False
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    body = json.dumps({"chat_id": TELEGRAM_CHAT_ID, "text": message, "parse_mode": "HTML"}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.loads(r.read())
    return data.get("ok", False)

def build_prompt() -> str:
    today = datetime.now()
    weekday = ["월", "화", "수", "목", "금", "토", "일"][today.weekday()]
    date_str = today.strftime(f"%Y년 %m월 %d일 ({weekday})")
    return f"""오늘은 {date_str}이야.
아래 AI 크리에이티브 툴 4개 각각에 대해 오늘 바로 복붙해서 쓸 수 있는 영어 프롬프트를 하나씩 만들어줘.
테마는 오늘 날짜, 계절, 요일 분위기에 맞게 잡아.

출력 형식 (이 형식 그대로, 다른 말 없이):

🎬 [Sora] 10초 영상
"(프롬프트)"

🖼 [Midjourney] 이미지
"/imagine (프롬프트) --ar 16:9 --v 6"

🎵 [Suno] BGM
"(장르, BPM, 분위기, 악기, 길이 포함 프롬프트)"

🎥 [Kling] 루프 영상
"(프롬프트)"

규칙:
- 각 프롬프트는 영어로, 큰따옴표 안에
- Sora: 짧고 시네마틱한 장면 묘사
- Midjourney: /imagine 명령어 포함, 파라미터 포함
- Suno: 장르/BPM/분위기/악기 구체적으로
- Kling: seamless loop에 어울리는 자연/추상적 장면
"""

def main():
    today = datetime.now().strftime("%Y-%m-%d")
    print(f"[creative-brief] {today} 시작")
    
    prompt = build_prompt()
    
    if DRY_RUN:
        print("[DRY-RUN] Gemini 호출 스킵")
        brief_content = """🎬 [Sora] 10초 영상
"A misty forest path in early spring morning, sunlight filtering through new leaves, cinematic 4K"

🖼 [Midjourney] 이미지
"/imagine Soft morning light through cafe window, steam rising from coffee cup, minimalist aesthetic --ar 16:9 --v 6"

🎵 [Suno] BGM
"Acoustic lo-fi, 85bpm, spring morning mood, guitar + light percussion, 2min loop"

🎥 [Kling] 루프 영상
"Cherry blossom petals falling gently in slow motion, seamless loop, soft pink and white tones"
"""
    else:
        print("[1/2] Gemini 프롬프트 생성 중...")
        brief_content = gemini_generate(prompt)
    
    message = f"🎨 <b>오늘의 크리에이티브 브리프</b> ({today})\n\n{brief_content.strip()}"
    
    print("[2/2] Telegram 전송 중...")
    print(message)
    
    if DRY_RUN:
        print("[DRY-RUN] Telegram 전송 스킵")
        return
    
    if telegram_send(message):
        print("[OK] 전송 완료")
    else:
        print("[ERROR] Telegram 전송 실패")
        sys.exit(1)

if __name__ == "__main__":
    main()
```

### 2. scripts/creative-brief.sh
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
source "$SCRIPT_DIR/secrets_load.sh" 2>/dev/null || true

exec python3 "$SCRIPT_DIR/creative-brief.py" "$@"
```

### 3. LaunchAgents plist (M1에 직접 설치)
경로: ~/Library/LaunchAgents/com.luma2.creative-brief.plist
매일 08:30 실행.

## 구현 순서
1. scripts/creative-brief.py 작성 (위 코드 기반으로)
2. scripts/creative-brief.sh 작성
3. 로컬에서 테스트: `python3 scripts/creative-brief.py --dry-run`
4. M1에 sync: `bash scripts/sync.sh` 또는 git push/pull
5. M1에 plist 설치 및 launchctl load

## 완료 기준
- `--dry-run` 모드: 정상 출력
- Telegram 실제 전송 테스트 성공
- launchd 등록 완료

## 참고 파일 (패턴 동일하게 따를 것)
- scripts/it-contents.sh — secrets 로드 패턴
- scripts/telegram-send.sh — Telegram 전송 패턴
- ~/Library/LaunchAgents/com.luma2.it-contents.plist — plist 템플릿
- scripts/env.sh — 환경 모듈 (반드시 source)
