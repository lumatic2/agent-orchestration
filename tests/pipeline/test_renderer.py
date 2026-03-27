from __future__ import annotations

from pipeline.templates.renderer import render_string


def test_render_string() -> None:
    assert render_string("Hello {NAME}", {"NAME": "World"}) == "Hello World"


def test_render_multiple() -> None:
    rendered = render_string("{A}-{B}-{A}", {"A": "x", "B": "y"})
    assert rendered == "x-y-x"


def test_render_missing_key() -> None:
    assert render_string("Value: {MISSING}", {}) == "Value: {MISSING}"
