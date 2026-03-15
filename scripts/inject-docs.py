#!/usr/bin/env python3
"""
inject-docs.py — JSON 문서 데이터 → 완성 HTML 조립

사용법:
  python3 inject-docs.py <docs.json> [--out /tmp/output.html]
  python3 inject-docs.py --validate <docs.json>
"""

import argparse
import copy
import html
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List


REPO_ROOT = Path(__file__).resolve().parent.parent
BASE_TEMPLATE_PATH = REPO_ROOT / "templates" / "docs" / "base.html"
COMPONENT_DIR = REPO_ROOT / "templates" / "docs" / "components"

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
    parser = argparse.ArgumentParser(description="Render docs HTML from docs JSON.")
    parser.add_argument("docs_json", nargs="?", help="Path to docs JSON")
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


def validate_schema(payload: Dict[str, Any]) -> List[str]:
    errors: List[str] = []
    if not isinstance(payload, dict):
        return ["root: JSON 루트는 object여야 합니다."]

    meta = payload.get("meta")
    sections = payload.get("sections")

    if not isinstance(meta, dict):
        errors.append("meta: object여야 합니다.")
    else:
        if not isinstance(meta.get("title"), str) or not meta.get("title", "").strip():
            errors.append("meta.title: 비어있지 않은 문자열이어야 합니다.")
        if not isinstance(meta.get("type"), str) or not meta.get("type", "").strip():
            errors.append("meta.type: 비어있지 않은 문자열이어야 합니다.")

    if not isinstance(sections, list) or not sections:
        errors.append("sections: 비어있지 않은 배열이어야 합니다.")
        return errors

    type_rules: Dict[str, List[str]] = {
        "cover": ["title", "subtitle", "type_label", "company", "date"],
        "section": ["heading", "body"],
        "bullet_section": ["heading", "items"],
        "table_section": ["heading", "headers", "rows"],
        "highlight_box": ["label", "text"],
        "two_col": ["heading", "left_heading", "left_items", "right_heading", "right_items"],
        "closing": ["text", "contact_name", "contact_email"],
    }

    for index, section in enumerate(sections, start=1):
        base_path = f"sections[{index}]"
        if not isinstance(section, dict):
            errors.append(f"{base_path}: object여야 합니다.")
            continue

        section_type = section.get("type")
        data = section.get("data")

        if not isinstance(section_type, str) or not section_type:
            errors.append(f"{base_path}.type: 비어있지 않은 문자열이어야 합니다.")
            continue

        if section_type not in type_rules:
            errors.append(f"{base_path}.type: 지원하지 않는 타입입니다 ({section_type}).")
            continue

        if not isinstance(data, dict):
            errors.append(f"{base_path}.data: object여야 합니다.")
            continue

        for key in type_rules[section_type]:
            if key not in data:
                errors.append(f"{base_path}.data.{key}: 필수 키가 누락되었습니다.")

        if section_type == "section":
            if "body" in data and not isinstance(data.get("body"), str):
                errors.append(f"{base_path}.data.body: 문자열이어야 합니다.")

        if section_type == "bullet_section" and "items" in data:
            items = data.get("items")
            if not isinstance(items, list):
                errors.append(f"{base_path}.data.items: 배열이어야 합니다.")
            else:
                for item_idx, item in enumerate(items, start=1):
                    item_path = f"{base_path}.data.items[{item_idx}]"
                    if isinstance(item, str):
                        continue
                    if not isinstance(item, dict):
                        errors.append(f"{item_path}: string 또는 object여야 합니다.")
                        continue
                    if "title" not in item:
                        errors.append(f"{item_path}.title: 필수 키가 누락되었습니다.")

        if section_type == "table_section":
            headers = data.get("headers")
            rows = data.get("rows")
            if "headers" in data:
                if not isinstance(headers, list) or not all(isinstance(h, str) for h in headers):
                    errors.append(f"{base_path}.data.headers: 문자열 배열이어야 합니다.")
            if "rows" in data:
                if not isinstance(rows, list):
                    errors.append(f"{base_path}.data.rows: 배열이어야 합니다.")
                else:
                    for row_idx, row in enumerate(rows, start=1):
                        if not isinstance(row, list):
                            errors.append(f"{base_path}.data.rows[{row_idx}]: 배열이어야 합니다.")

        if section_type == "two_col":
            left_items = data.get("left_items")
            right_items = data.get("right_items")
            if "left_items" in data and (
                not isinstance(left_items, list) or not all(isinstance(v, str) for v in left_items)
            ):
                errors.append(f"{base_path}.data.left_items: 문자열 배열이어야 합니다.")
            if "right_items" in data and (
                not isinstance(right_items, list) or not all(isinstance(v, str) for v in right_items)
            ):
                errors.append(f"{base_path}.data.right_items: 문자열 배열이어야 합니다.")

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


def preprocess_section_data(section_type: str, raw_data: Dict[str, Any]) -> Dict[str, Any]:
    data = copy.deepcopy(raw_data)

    if section_type == "cover":
        data.setdefault("subtitle", "")

    if section_type == "highlight_box":
        data.setdefault("sub_text", "")

    if section_type == "closing":
        data.setdefault("contact_phone", "")
        contacts = [data.get("contact_name", ""), data.get("contact_email", ""), data.get("contact_phone", "")]
        data["contact_line"] = " | ".join([str(v) for v in contacts if str(v).strip()])

    if section_type == "bullet_section":
        converted: List[Dict[str, str]] = []
        for item in data.get("items", []):
            if isinstance(item, str):
                converted.append({"title": item, "desc": ""})
            else:
                converted.append(
                    {
                        "title": str(item.get("title", "")),
                        "desc": str(item.get("desc", "")),
                    }
                )
        data["items"] = converted

    if section_type == "table_section":
        headers = data.get("headers", [])
        rows = data.get("rows", [])
        head_cells = "".join(f"<th>{html.escape(str(header))}</th>" for header in headers)
        body_rows = []
        for row in rows:
            row_cells = "".join(f"<td>{html.escape(str(cell))}</td>" for cell in row)
            body_rows.append(f"<tr>{row_cells}</tr>")
        data["table_thead_html"] = f"<thead><tr>{head_cells}</tr></thead>"
        data["table_tbody_html"] = f"<tbody>{''.join(body_rows)}</tbody>"

    return data


def build_html(payload: Dict[str, Any]) -> str:
    if not BASE_TEMPLATE_PATH.exists():
        raise RenderError(f"base 템플릿을 찾을 수 없습니다: {BASE_TEMPLATE_PATH}")

    base_css = BASE_TEMPLATE_PATH.read_text(encoding="utf-8")
    sections = payload["sections"]
    cover_parts: List[str] = []
    body_parts: List[str] = []

    for index, section in enumerate(sections, start=1):
        section_type = section["type"]
        section_data = preprocess_section_data(section_type, section["data"])
        component_path = COMPONENT_DIR / f"{section_type}.html"

        if not component_path.exists():
            raise RenderError(f"{index}번째 섹션: 컴포넌트 파일 없음 ({component_path})")

        component_template = component_path.read_text(encoding="utf-8")
        try:
            rendered = render_template(component_template, section_data)
        except RenderError as exc:
            raise RenderError(f"{index}번째 섹션({section_type}) 렌더 실패: {exc}") from exc

        if section_type == "cover":
            cover_parts.append(rendered)
        else:
            body_parts.append(rendered)

    # cover는 단독 페이지, 나머지는 .doc-body로 묶어 자연 흐름
    output_parts = cover_parts[:]
    if body_parts:
        output_parts.append(
            '<div class="doc-body">\n' + "\n".join(body_parts) + "\n</div>"
        )

    title = payload.get("meta", {}).get("title", "Document")
    return (
        "<!doctype html>\n"
        "<html lang=\"ko\">\n"
        "<head>\n"
        "  <meta charset=\"utf-8\" />\n"
        "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />\n"
        f"  <title>{title}</title>\n"
        f"{base_css}\n"
        "</head>\n"
        "<body>\n"
        f"{chr(10).join(output_parts)}\n"
        "</body>\n"
        "</html>\n"
    )


def main() -> int:
    args = parse_args()
    if not args.docs_json:
        print("사용법 오류: docs.json 경로를 지정하세요.", file=sys.stderr)
        return 2

    payload = load_json(Path(args.docs_json))
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
