from __future__ import annotations

from pathlib import Path


def render(template_path: Path, variables: dict[str, str]) -> str:
    template = template_path.read_text(encoding="utf-8")
    return render_string(template, variables)


def render_string(template: str, variables: dict[str, str]) -> str:
    output = template
    for key, value in variables.items():
        output = output.replace(f"{{{key}}}", value)
    return output
