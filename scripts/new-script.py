#!/usr/bin/env python3
# new-script.py — scripts/ 디렉토리에 새 Python 스크립트 뼈대 생성
# Usage: python3 new-script.py <스크립트명> ["설명"]
#
# 예시:
#   python3 new-script.py report.py "일간 리포트 생성"

from __future__ import annotations

import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

TEMPLATE = '''\
#!/usr/bin/env python3
"""
{name} — {desc}

사용법:
  python3 {name} <arg>
"""

from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 2:
        print(f"Usage: python3 {name} <arg>", file=sys.stderr)
        return 1

    arg = sys.argv[1]
    # ── 메인 로직 ────────────────────────────────────────────

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'''


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: python3 new-script.py <스크립트명> [\"설명\"]", file=sys.stderr)
        return 1

    name = sys.argv[1]
    desc = sys.argv[2] if len(sys.argv) > 2 else ""

    if not name.endswith(".py"):
        name += ".py"

    out = SCRIPT_DIR / name
    if out.exists():
        print(f"[ERROR] 이미 존재합니다: {out}", file=sys.stderr)
        return 1

    out.write_text(TEMPLATE.format(name=name, desc=desc), encoding="utf-8")
    out.chmod(0o755)
    print(f"생성됨: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
