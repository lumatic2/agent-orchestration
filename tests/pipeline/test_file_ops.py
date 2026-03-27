from __future__ import annotations

import json

from pipeline.core.file_ops import atomic_write, atomic_write_json, safe_read


def test_atomic_write(tmp_path) -> None:
    path = tmp_path / "sample.txt"
    atomic_write(path, "hello")
    assert path.read_text(encoding="utf-8") == "hello"


def test_atomic_write_json(tmp_path) -> None:
    path = tmp_path / "sample.json"
    data = {"a": 1, "b": "x"}
    atomic_write_json(path, data)
    assert json.loads(path.read_text(encoding="utf-8")) == data


def test_safe_read_existing(tmp_path) -> None:
    path = tmp_path / "exists.txt"
    path.write_text("value", encoding="utf-8")
    assert safe_read(path) == "value"


def test_safe_read_missing(tmp_path) -> None:
    path = tmp_path / "missing.txt"
    assert safe_read(path) == ""
