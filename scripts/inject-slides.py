#!/usr/bin/env python3
"""
inject-slides.py — JSON 슬라이드 데이터 → 완성 HTML 조립

사용법:
  python3 inject-slides.py <slides.json> [--out /tmp/output.html]
  python3 inject-slides.py --validate <slides.json>   # JSON 유효성만 검사

출력:
  --out 지정 시 파일 저장, 없으면 stdout
"""

import argparse
import copy
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List


REPO_ROOT = Path(__file__).resolve().parent.parent
BASE_TEMPLATE_PATH = REPO_ROOT / "templates" / "slides" / "base.html"
COMPONENT_DIR = REPO_ROOT / "templates" / "slides" / "components"
ICONS_PATH = REPO_ROOT / "templates" / "slides" / "icons.json"

_icons_cache: Dict[str, str] | None = None


def _load_icons() -> Dict[str, str]:
    global _icons_cache
    if _icons_cache is None:
        if ICONS_PATH.exists():
            _icons_cache = json.loads(ICONS_PATH.read_text(encoding="utf-8"))
        else:
            _icons_cache = {}
    return _icons_cache


def resolve_icons(data: Any) -> Any:
    """icon 필드 값이 icons.json 키와 일치하면 SVG 코드로 치환."""
    icons = _load_icons()
    if isinstance(data, dict):
        return {
            k: icons[v] if k == "icon" and isinstance(v, str) and v in icons else resolve_icons(v)
            for k, v in data.items()
        }
    if isinstance(data, list):
        return [resolve_icons(item) for item in data]
    return data

VAR_PATTERN = re.compile(r"\{\{\s*([a-zA-Z0-9_\.]+)\s*\}\}")
FOR_PATTERN = re.compile(
    r"\{%\s*for\s+([a-zA-Z_][a-zA-Z0-9_]*)\s+in\s+([a-zA-Z0-9_\.]+)\s*%\}(.*?)\{%\s*endfor\s*%\}",
    re.DOTALL,
)


class ValidationError(Exception):
    pass


class RenderError(Exception):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render slide HTML from slides JSON.")
    parser.add_argument("slides_json", nargs="?", help="Path to slides JSON")
    parser.add_argument("--out", help="Output HTML path")
    parser.add_argument("--validate", action="store_true", help="Only validate JSON")
    return parser.parse_args()


def load_json(path: Path) -> Dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ValidationError(f"입력 파일을 찾을 수 없습니다: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValidationError(f"JSON 파싱 실패 ({path}): line {exc.lineno}, column {exc.colno}") from exc


def expect_type(
    errors: List[str],
    value: Any,
    expected: type,
    path: str,
    message: str,
) -> None:
    if not isinstance(value, expected):
        errors.append(f"{path}: {message}")


def validate_schema(payload: Dict[str, Any]) -> List[str]:
    errors: List[str] = []
    if not isinstance(payload, dict):
        return ["root: JSON 루트는 object여야 합니다."]

    meta = payload.get("meta")
    slides = payload.get("slides")

    if not isinstance(meta, dict):
        errors.append("meta: object여야 합니다.")
    elif not isinstance(meta.get("title"), str) or not meta.get("title", "").strip():
        errors.append("meta.title: 비어있지 않은 문자열이어야 합니다.")

    if not isinstance(slides, list) or not slides:
        errors.append("slides: 비어있지 않은 배열이어야 합니다.")
        return errors

    type_rules: Dict[str, Dict[str, Any]] = {
        "title_panel": {
            "required": ["title", "subtitle", "points"],
            "lists": {"points": {"max": 4, "item": str}},
        },
        "card_grid": {
            "required": ["badge", "title", "cards"],
            "lists": {
                "cards": {
                    "max": 6,
                    "item": dict,
                    "required_keys": ["icon", "title", "desc"],
                }
            },
        },
        "numbered_list": {
            "required": ["badge", "title", "subtitle", "items"],
            "lists": {
                "items": {
                    "max": 4,
                    "item": dict,
                    "required_keys": ["num", "title", "desc"],
                }
            },
        },
        "bar_chart": {
            "required": ["badge", "title", "bars", "hero_number", "hero_label", "sub_stats"],
            "lists": {
                "bars": {
                    "item": dict,
                    "required_keys": ["label", "value", "max"],
                },
                "sub_stats": {
                    "item": dict,
                    "required_keys": ["label", "value"],
                },
            },
        },
        "big_statement": {
            "required": ["badge", "line1", "line2", "line3"],
            "lists": {},
        },
        "comparison_table": {
            "required": ["badge", "title", "left_label", "right_label", "rows"],
            "lists": {
                "rows": {
                    "item": dict,
                    "required_keys": ["aspect", "left", "right", "highlight"],
                }
            },
        },
        "timeline": {
            "required": ["badge", "title", "steps"],
            "lists": {
                "steps": {
                    "max": 5,
                    "item": dict,
                    "required_keys": ["year", "title", "desc"],
                }
            },
        },
        "quote_close": {
            "required": ["quote", "author"],
            "lists": {},
        },
        "before_after": {
            "required": ["left_label", "right_label", "left_image", "right_image"],
            "lists": {},
        },
    }

    for index, slide in enumerate(slides, start=1):
        base_path = f"slides[{index}]"
        if not isinstance(slide, dict):
            errors.append(f"{base_path}: object여야 합니다.")
            continue

        slide_type = slide.get("type")
        data = slide.get("data")

        if not isinstance(slide_type, str) or not slide_type:
            errors.append(f"{base_path}.type: 비어있지 않은 문자열이어야 합니다.")
            continue

        if slide_type not in type_rules:
            errors.append(f"{base_path}.type: 지원하지 않는 타입입니다 ({slide_type}).")
            continue

        if not isinstance(data, dict):
            errors.append(f"{base_path}.data: object여야 합니다.")
            continue

        rules = type_rules[slide_type]
        for key in rules["required"]:
            if key not in data:
                errors.append(f"{base_path}.data.{key}: 필수 키가 누락되었습니다.")

        for list_key, list_rule in rules["lists"].items():
            if list_key not in data:
                continue

            value = data.get(list_key)
            if not isinstance(value, list):
                errors.append(f"{base_path}.data.{list_key}: 배열이어야 합니다.")
                continue

            max_items = list_rule.get("max")
            if max_items is not None and len(value) > max_items:
                errors.append(
                    f"{base_path}.data.{list_key}: 최대 {max_items}개까지 허용됩니다 (현재 {len(value)}개)."
                )

            required_keys = list_rule.get("required_keys", [])
            item_type = list_rule.get("item")
            for item_index, item in enumerate(value, start=1):
                item_path = f"{base_path}.data.{list_key}[{item_index}]"
                if item_type and not isinstance(item, item_type):
                    errors.append(f"{item_path}: {item_type.__name__} 타입이어야 합니다.")
                    continue

                if required_keys:
                    for child_key in required_keys:
                        if child_key not in item:
                            errors.append(f"{item_path}.{child_key}: 필수 키가 누락되었습니다.")

                if list_key == "rows" and isinstance(item, dict):
                    highlight = item.get("highlight")
                    if highlight not in (None, "left", "right"):
                        errors.append(f"{item_path}.highlight: null, 'left', 'right' 중 하나여야 합니다.")

                if list_key == "bars" and isinstance(item, dict):
                    try:
                        max_value = float(item.get("max"))
                        value_num = float(item.get("value"))
                        if max_value <= 0:
                            errors.append(f"{item_path}.max: 0보다 커야 합니다.")
                        elif value_num < 0:
                            errors.append(f"{item_path}.value: 0 이상이어야 합니다.")
                    except (TypeError, ValueError):
                        errors.append(f"{item_path}.value/max: 숫자여야 합니다.")

    return errors


def resolve_expr(expr: str, context: Dict[str, Any]) -> Any:
    parts = expr.split(".")
    value: Any = context
    for part in parts:
        if isinstance(value, dict):
            if part not in value:
                raise RenderError(f"템플릿 키 누락: {expr}")
            value = value[part]
        else:
            raise RenderError(f"잘못된 템플릿 경로: {expr}")
    return value


def to_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False)
    return str(value)


def render_template(template: str, context: Dict[str, Any]) -> str:
    rendered = template

    while True:
        match = FOR_PATTERN.search(rendered)
        if not match:
            break

        var_name, iter_expr, block = match.groups()
        iterable = resolve_expr(iter_expr, context)
        if not isinstance(iterable, list):
            raise RenderError(f"for-loop 대상은 배열이어야 합니다: {iter_expr}")

        parts: List[str] = []
        for item in iterable:
            child = dict(context)
            child[var_name] = item
            parts.append(render_template(block, child))
        rendered = rendered[: match.start()] + "".join(parts) + rendered[match.end() :]

    def replace_var(m: re.Match[str]) -> str:
        expr = m.group(1)
        value = resolve_expr(expr, context)
        return to_text(value)

    return VAR_PATTERN.sub(replace_var, rendered)


def preprocess_slide_data(slide_type: str, raw_data: Dict[str, Any]) -> Dict[str, Any]:
    data = copy.deepcopy(raw_data)
    data = resolve_icons(data)

    if slide_type == "bar_chart":
        for bar in data.get("bars", []):
            value = float(bar["value"])
            max_value = float(bar["max"])
            width = 0.0 if max_value <= 0 else max(0.0, min(100.0, (value / max_value) * 100.0))
            bar["width_percent"] = f"{width:.2f}".rstrip("0").rstrip(".")

    if slide_type == "comparison_table":
        for row in data.get("rows", []):
            highlight = row.get("highlight")
            row["left_class"] = "highlight" if highlight == "left" else ""
            row["right_class"] = "highlight" if highlight == "right" else ""

    return data


def build_html(payload: Dict[str, Any]) -> str:
    if not BASE_TEMPLATE_PATH.exists():
        raise RenderError(f"base 템플릿을 찾을 수 없습니다: {BASE_TEMPLATE_PATH}")

    base_css = BASE_TEMPLATE_PATH.read_text(encoding="utf-8")
    slides = payload["slides"]
    deck: List[str] = []

    for index, slide in enumerate(slides, start=1):
        slide_type = slide["type"]
        slide_data = preprocess_slide_data(slide_type, slide["data"])
        component_path = COMPONENT_DIR / f"{slide_type}.html"

        if not component_path.exists():
            raise RenderError(f"{index}번째 슬라이드: 컴포넌트 파일 없음 ({component_path})")

        component_template = component_path.read_text(encoding="utf-8")
        try:
            html = render_template(component_template, slide_data)
        except RenderError as exc:
            raise RenderError(f"{index}번째 슬라이드({slide_type}) 렌더 실패: {exc}") from exc

        deck.append(f'<section class="slide slide-{slide_type}">\n{html}\n</section>')

    title = payload.get("meta", {}).get("title", "Slides")
    return (
        "<!doctype html>\n"
        "<html lang=\"ko\">\n"
        "<head>\n"
        "  <meta charset=\"utf-8\" />\n"
        "  <meta name=\"viewport\" content=\"width=1280, initial-scale=1\" />\n"
        f"  <title>{title}</title>\n"
        f"{base_css}\n"
        "</head>\n"
        "<body>\n"
        "  <main class=\"deck\">\n"
        f"{chr(10).join(deck)}\n"
        "  </main>\n"
        "</body>\n"
        "</html>\n"
    )


def main() -> int:
    args = parse_args()
    if not args.slides_json:
        print("사용법 오류: slides.json 경로를 지정하세요.", file=sys.stderr)
        return 2

    payload = load_json(Path(args.slides_json))
    errors = validate_schema(payload)

    if args.validate:
        if errors:
            print("유효성 검사 실패:")
            for err in errors:
                print(f"- {err}")
            return 1
        print("유효성 검사 통과")
        return 0

    if errors:
        print("유효성 검사 실패:", file=sys.stderr)
        for err in errors:
            print(f"- {err}", file=sys.stderr)
        return 1

    try:
        html = build_html(payload)
    except RenderError as exc:
        print(f"렌더 오류: {exc}", file=sys.stderr)
        return 1

    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(html, encoding="utf-8")
        print(str(out_path))
    else:
        print(html)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
