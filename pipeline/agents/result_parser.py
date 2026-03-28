from __future__ import annotations

import json
import re
from typing import Any


_CONTENT_WITH_USAGE = re.compile(
    r"^--- (Codex Summary|Codex Result|Gemini Result|ChatGPT Result) ---\s*(.*?)\s*^--- Token Usage ---",
    re.DOTALL | re.MULTILINE,
)
_CONTENT_NO_USAGE = re.compile(
    r"^--- (Codex Summary|Codex Result|Gemini Result|ChatGPT Result) ---\s*(.*)",
    re.DOTALL | re.MULTILINE,
)
_GEMINI_ERROR = re.compile(
    r"^(Attempt \d+ failed|GaxiosError|  config:|  response:|  status:|"
    r"  headers:|  body:|  signal:|  retry:|  data:|    url:|    method:|"
    r"    params:|    responseType:|    paramsSerializer:|    validateStatus:|"
    r"    errorRedactor:|  \}|  \]|\}|\]|'[a-z-]+':)",
)
_LOG_PATTERN = re.compile(r"^\[(LOG|QUEUE|ROUTER|DISPATCH|CHECKLIST|SUBAGENT|UA|RATE_LIMIT|FALLBACK|VAULT|GUARD|QUEUE_DIR|MODE)\]")
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


def _strip_gemini_errors(text: str) -> str:
    lines = []
    for line in text.splitlines():
        if _GEMINI_ERROR.match(line.strip()):
            continue
        lines.append(line)
    return "\n".join(lines).strip()


def _unescape_markdown(text: str) -> str:
    """Undo JSON-style escaping that LLMs sometimes emit (e.g. literal \\n, \\#\\#)."""
    # Actual newlines first (\\r\\n before \\n)
    text = text.replace("\\r\\n", "\n").replace("\\n", "\n")
    text = text.replace("\\t", "\t")
    # Unescape markdown-significant chars: \# → #, \* → *, \_ → _, etc.
    text = re.sub(r"\\([#*_\[\]`>~|])", r"\1", text)
    return text


def extract_content(raw: str) -> str:
    match = _CONTENT_WITH_USAGE.search(raw)
    if match:
        return _unescape_markdown(_strip_noise(match.group(2)))
    match = _CONTENT_NO_USAGE.search(raw)
    if match:
        content = _strip_noise(match.group(2))
        return _unescape_markdown(_strip_gemini_errors(content))
    return _unescape_markdown(_strip_noise(raw))


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
