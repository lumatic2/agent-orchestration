#!/usr/bin/env python3
"""codex-usage.py — 오늘 Codex 호출 횟수 조회."""

import io
import json
import re
import shutil
import subprocess
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")
from datetime import datetime, timezone, timedelta
from pathlib import Path

KST = timezone(timedelta(hours=9))


def today_kst() -> str:
    return datetime.now(KST).strftime("%Y-%m-%d")


def _parse_dt(s: str) -> datetime:
    """7자리 소수점 포함 ISO 날짜를 파싱."""
    # 소수점 이하 6자리로 통일 후 파싱
    s = re.sub(r'(\.\d{6})\d+', r'\1', s.rstrip("Z")) + "+00:00"
    return datetime.fromisoformat(s)


def count_cloud_tasks(today: str) -> tuple[int, list[dict]]:
    """codex cloud list --json에서 오늘 task 수 반환."""
    codex_bin = shutil.which("codex") or "codex"
    try:
        result = subprocess.run(
            [codex_bin, "cloud", "list", "--json", "--limit", "20"],
            capture_output=True, timeout=15, shell=False
        )
        data = json.loads(result.stdout.decode("utf-8", errors="replace"))
        tasks = data.get("tasks", [])
    except Exception as e:
        print(f"[cloud] 조회 실패: {e}", file=sys.stderr)
        return 0, []

    today_tasks = [
        t for t in tasks
        if t.get("updated_at", "").startswith(today)
    ]
    return len(today_tasks), today_tasks


def count_local_sessions(today: str) -> int:
    """~/.codex/session_index.jsonl에서 오늘 세션 수 반환."""
    path = Path.home() / ".codex" / "session_index.jsonl"
    if not path.exists():
        return 0

    count = 0
    with path.open(encoding="utf-8") as f:
        for line in f:
            try:
                entry = json.loads(line)
                updated = entry.get("updated_at", "")
                # UTC → KST 변환 (소수점 7자리 대응)
                dt_utc = _parse_dt(updated)
                if dt_utc.astimezone(KST).strftime("%Y-%m-%d") == today:
                    count += 1
            except Exception:
                continue
    return count


def main():
    today = today_kst()
    cloud_count, cloud_tasks = count_cloud_tasks(today)
    local_count = count_local_sessions(today)

    print(f"[{today} KST] Codex 호출 현황")
    print(f"  Cloud tasks : {cloud_count}개")
    print(f"  Local sessions: {local_count}개")
    print(f"  합계        : {cloud_count + local_count}개")

    if cloud_tasks:
        print("\nCloud tasks 상세:")
        for t in cloud_tasks:
            status = t.get("status", "?")
            title = t.get("title", "(no title)")[:50]
            print(f"  [{status:8}] {title}")


if __name__ == "__main__":
    main()
