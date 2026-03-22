#!/usr/bin/env python3

import asyncio
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import List, Optional

try:
    from telegram import Update
    from telegram.ext import Application, ContextTypes, MessageHandler, filters
except ImportError:
    print("python-telegram-bot is not installed. Run: pip3 install python-telegram-bot", file=sys.stderr)
    raise


SCRIPT_DIR = Path(__file__).resolve().parent
BASE_DIR = SCRIPT_DIR.parent
DATA_FILE = BASE_DIR / "data" / "latest-topics.json"
GEMINI_DEFAULT = "/Users/luma2/.nvm/versions/node/v24.14.0/bin/gemini"
MAX_TELEGRAM_LEN = 4096


def get_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"{name} is not set")
    return value


def parse_topic_number(text: str) -> Optional[int]:
    s = text.strip()
    m = re.fullmatch(r"(10|[1-9])", s)
    if m:
        return int(m.group(1))

    m = re.fullmatch(r"주제\s*(10|[1-9])", s)
    if m:
        return int(m.group(1))
    return None


def load_topic(index: int) -> Optional[str]:
    if not DATA_FILE.exists():
        return None
    try:
        payload = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    except Exception:
        return None
    topics = payload.get("topics", [])
    if not isinstance(topics, list):
        return None
    if 1 <= index <= len(topics):
        topic = topics[index - 1]
        if isinstance(topic, str) and topic.strip():
            return topic.strip()
    return None


def split_message(text: str, limit: int = MAX_TELEGRAM_LEN) -> List[str]:
    if len(text) <= limit:
        return [text]

    chunks = []
    current = []
    current_len = 0
    for line in text.splitlines(keepends=True):
        line_len = len(line)
        if line_len > limit:
            if current:
                chunks.append("".join(current))
                current = []
                current_len = 0
            start = 0
            while start < line_len:
                chunks.append(line[start : start + limit])
                start += limit
            continue
        if current_len + line_len > limit:
            chunks.append("".join(current))
            current = [line]
            current_len = line_len
        else:
            current.append(line)
            current_len += line_len
    if current:
        chunks.append("".join(current))
    return chunks


def gemini_command() -> str:
    custom = os.getenv("GEMINI_BIN", "").strip()
    if custom:
        return custom
    if Path(GEMINI_DEFAULT).exists():
        return GEMINI_DEFAULT
    return "gemini"


def build_prompt(topic: str) -> str:
    return f"""
아래 주제로 유튜브 스크립트 초안을 작성해줘.

[채널 컨텍스트]
- 채널: 루마 채널
- 핵심 메시지: AI 시대 나는 이렇게 살고 있다
- 톤 비중: 진지 6 : 가벼움 4
- 대상: AI를 일/삶에 적용하려는 성인 실무자

[요청 주제]
{topic}

[출력 형식]
- 제목 1개
- 섹션 구성: 도입 -> 본론1 -> 본론2 -> 본론3(선택) -> 본론4(선택) -> 마무리
- 각 섹션마다 반드시 아래 2가지를 포함:
  1) 나레이션: 2~4문장
  2) 슬라이드 힌트: content.json에서 바로 쓸 수 있는 slide_type과 핵심 키워드
- 총 분량: 전체 3~5분 분량
- 한국어로 작성

[예시 포맷]
# 제목
...

## 도입
나레이션: ...
슬라이드 힌트: slide_type=title_panel, keywords=[...]
""".strip()


def generate_script(topic: str) -> str:
    prompt = build_prompt(topic)
    cmd = [gemini_command(), "--yolo", "-m", "gemini-2.5-flash", "-p", prompt]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()
        raise RuntimeError(f"Gemini failed: {err[:500]}")

    output = (proc.stdout or "").strip()
    if not output:
        raise RuntimeError("Gemini returned empty output")
    return output


async def on_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.message is None or update.message.text is None:
        return

    configured_chat = context.bot_data.get("target_chat_id")
    if configured_chat is not None and update.effective_chat is not None:
        if update.effective_chat.id != configured_chat:
            return

    index = parse_topic_number(update.message.text)
    if index is None:
        return

    topic = load_topic(index)
    if not topic:
        await update.message.reply_text("최근 주제 추천이 없습니다")
        return

    await update.message.reply_text("✍️ 스크립트 작성 중...")

    try:
        script = await asyncio.to_thread(generate_script, topic)
    except Exception as exc:
        await update.message.reply_text(f"스크립트 생성 실패: {exc}")
        return

    header = f"[주제 {index}] {topic}\n\n"
    chunks = split_message(header + script)
    for chunk in chunks:
        await update.message.reply_text(chunk)


def main() -> None:
    token = get_env("TELEGRAM_BOT_TOKEN_IT")
    chat_id_raw = get_env("TELEGRAM_CHAT_ID_CONTENT")
    try:
        target_chat_id = int(chat_id_raw)
    except ValueError as exc:
        raise RuntimeError(f"Invalid TELEGRAM_CHAT_ID_CONTENT: {chat_id_raw}") from exc

    app = Application.builder().token(token).build()
    app.bot_data["target_chat_id"] = target_chat_id
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, on_message))
    app.run_polling(close_loop=False)


if __name__ == "__main__":
    main()
