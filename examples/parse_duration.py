import re
import sys


def parse_duration(text: str) -> int:
    """Convert a duration like "1h30m15s" to total seconds."""
    s = text.strip().lower()

    if "-" in s:
        raise ValueError("negative durations not supported")
    if "." in s or "," in s:
        raise ValueError("fractional values not supported")
    if not s:
        raise ValueError(f"invalid duration: {text}")

    pattern = re.fullmatch(r"^(?:(\d+)([smhd]))+$", s)
    if not pattern:
        if re.fullmatch(r"^\d+$", s):
            raise ValueError("missing unit")
        raise ValueError(f"invalid duration: {text}")

    total = 0
    seen = set()
    multipliers = {"s": 1, "m": 60, "h": 3600, "d": 86400}

    for m in re.finditer(r"(\d+)([smhd])", s):
        amount = int(m.group(1))
        unit = m.group(2)
        if unit in seen:
            raise ValueError(f"duplicate unit: {unit}")
        seen.add(unit)
        total += amount * multipliers[unit]

    return total


if __name__ == "__main__":
    print(parse_duration(sys.argv[1]))
