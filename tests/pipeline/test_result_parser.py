from __future__ import annotations

from pipeline.agents.result_parser import extract_content, extract_token_usage


def test_extract_content_codex() -> None:
    raw = "--- Codex Summary ---\nhello world\n--- Token Usage ---\n{}"
    assert extract_content(raw) == "hello world"


def test_extract_content_gemini() -> None:
    raw = "--- Gemini Result ---\nresult text\n--- Token Usage ---\n{}"
    assert extract_content(raw) == "result text"


def test_extract_content_no_markers() -> None:
    assert extract_content("plain text") == "plain text"


def test_strip_noise() -> None:
    raw = "\n".join(
        [
            "[LOG] running",
            "useful line",
            "    at Module.run (file.js:10:2)",
            "Node.js v20.0.0",
            "another useful line",
        ]
    )
    assert extract_content(raw) == "useful line\nanother useful line"


def test_extract_token_usage() -> None:
    raw = "--- Token Usage ---\n{\"prompt\": 10, \"completion\": 20}"
    assert extract_token_usage(raw) == {"prompt": 10, "completion": 20}


def test_extract_token_usage_missing() -> None:
    assert extract_token_usage("no usage block") is None
