#!/usr/bin/env python3
"""UserPromptSubmit hook — inject unread job-watcher completions into Claude context.

Reads ~/.claude/hooks/job-watcher-queue.jsonl from a byte-offset cursor,
emits a <system-reminder> block with any new entries, and advances the cursor.
Silent (no output) when there is nothing new.

Failures are swallowed — this hook must never block a user prompt.
"""
import json
import os
import sys
from pathlib import Path

# Windows default stdout is cp949 (on KR locales) which cannot encode
# emoji/CJK chars. Force UTF-8 so emission never fails on characters.
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

HOOK_DIR = Path.home() / ".claude" / "hooks"
QUEUE = HOOK_DIR / "job-watcher-queue.jsonl"
CURSOR = HOOK_DIR / ".job-watcher-inject.cursor"


def _log_error(msg: str) -> None:
    try:
        with (HOOK_DIR / "job-watcher.log").open("a", encoding="utf-8") as fh:
            fh.write(f"[inject-hook] {msg}\n")
    except Exception:
        pass


def _write_cursor_atomic(offset: int) -> None:
    # Write via temp file + os.replace so a crash mid-write cannot leave
    # a truncated cursor file that we'd misread as offset 0 on next run.
    tmp = CURSOR.parent / (CURSOR.name + ".tmp")
    tmp.write_text(str(offset))
    os.replace(tmp, CURSOR)


def main() -> int:
    try:
        if not QUEUE.exists():
            return 0
        size = QUEUE.stat().st_size
        try:
            offset = int(CURSOR.read_text().strip()) if CURSOR.exists() else 0
        except Exception:
            offset = 0
        # If the queue was truncated/rotated, reset cursor.
        if offset > size:
            offset = 0
        if offset >= size:
            return 0
        with QUEUE.open("rb") as fh:
            fh.seek(offset)
            # Bound the read to the size we stat'd. If the queue grew
            # between stat() and read(), leave the extra bytes for the
            # next invocation instead of reading past our advance point.
            raw = fh.read(size - offset)
        # Only advance past complete, newline-terminated records. If a
        # writer's append straddles our stat/read window, the trailing
        # partial line stays in the queue for the next invocation rather
        # than being silently dropped by the JSONDecodeError branch below.
        last_nl = raw.rfind(b"\n")
        if last_nl < 0:
            return 0
        complete = raw[: last_nl + 1]
        new_offset = offset + len(complete)
        chunk = complete.decode("utf-8", errors="replace")
        entries = []
        for line in chunk.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue
        if not entries:
            # Empty batch is safe to skip forward — no delivery to protect.
            try:
                _write_cursor_atomic(new_offset)
            except Exception as err:
                _log_error(f"cursor write failed (empty batch): {err}")
            return 0

        # Emit a system-reminder block. Claude Code forwards hook stdout as
        # additional prompt context, so this becomes visible to the assistant.
        lines = ["<job-watcher-updates>"]
        lines.append(
            f"다음은 백그라운드 codex/gemini 잡 완료 알림 {len(entries)}건입니다 "
            "(마지막으로 본 시점 이후). 사용자에게 굳이 다시 알릴 필요는 없지만, "
            "관련 후속 작업 판단에 반영하세요."
        )
        for e in entries:
            icon = "✅" if e.get("ok") else "❌"
            kind = e.get("kind", "?")
            proj = e.get("project") or "(unknown)"
            model = e.get("model") or "(default)"
            effort = e.get("effort")
            model_str = f"{model} (effort: {effort})" if effort else model
            dur = e.get("duration") or "?"
            prompt = e.get("prompt") or ""
            status = e.get("statusKo") or ("완료" if e.get("ok") else "실패")
            lines.append(
                f"- {icon} {kind} {e.get('id','?')} {status} | "
                f"프로젝트: {proj} | 모델: {model_str} | 소요: {dur}"
                + (f" | 작업: {prompt}" if prompt else "")
            )
        lines.append("</job-watcher-updates>")
        payload = "\n".join(lines) + "\n"
        # Emit FIRST, then advance cursor. If stdout write raises, the
        # outer except catches it and the cursor stays put — next run
        # redelivers the batch rather than silently dropping it.
        sys.stdout.write(payload)
        sys.stdout.flush()
        try:
            _write_cursor_atomic(new_offset)
        except Exception as err:
            # Emission already succeeded; a cursor failure here means the
            # next run will re-emit this batch. Duplicate > drop.
            _log_error(f"cursor write failed after emit: {err}")
    except Exception as err:
        _log_error(f"error: {err}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
