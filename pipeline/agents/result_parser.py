from __future__ import annotations

import json
import re
from typing import Any


_CONTENT_PATTERN = re.compile(
    r"^--- (Codex Summary|Codex Result|Gemini Result|ChatGPT Result) ---\s*(.*?)\s*^--- Token Usage ---",
    re.DOTALL | re.MULTILINE,
)
_LOG_PATTERN = re.compile(r"^\[(LOG|QUEUE)\]")
_STACK_PATTERN = re.compile(r"^\s*at\s+")
_NODE_VERSION_PATTERN = re.compile(r"^Node\.js v\d+")


def _strip_noise(text: str) -> str:
    lines: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if _LOG_PATTERN.match(stripped):
            continue
        if _STACK_PATTERN.match(line):
            continue
        if _NODE_VERSION_PATTERN.match(stripped):
            continue
        lines.append(line)
    return "\n".join(lines).strip()


def _extract_balanced_json(text: str) -> str | None:
    start = text.find("{")
    if start == -1:
        return None
    depth = 0
    in_string = False
    escape = False
    for idx in range(start, len(text)):
        char = text[idx]
        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start : idx + 1]
    return None


def extract_content(raw: str) -> str:
    match = _CONTENT_PATTERN.search(raw)
    if not match:
        return _strip_noise(raw)
    return _strip_noise(match.group(2))


def extract_token_usage(raw: str) -> dict[str, Any] | None:
    marker = "--- Token Usage ---"
    index = raw.find(marker)
    if index == -1:
        return None
    block = raw[index + len(marker) :].strip()
    if not block:
        return None
    json_text = _extract_balanced_json(block)
    if not json_text:
        return None
    try:
        parsed = json.loads(json_text)
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None
