import argparse
import json
import mimetypes
import os
import sys
import textwrap
import uuid
import urllib.error
import urllib.parse
import urllib.request
import re

NOTION_API_BASE = "https://api.notion.com/v1"
DEFAULT_NOTION_VERSION = "2022-06-28"

class NotionApiError(RuntimeError):
    def __init__(self, status: int, reason: str, payload: dict):
        super().__init__(f"Notion API error: HTTP {status} {reason}")
        self.status = status
        self.reason = reason
        self.payload = payload


def _env(name: str, required: bool = True) -> str | None:
    value = os.getenv(name)
    if required and not value:
        print(f"Missing env var: {name}", file=sys.stderr)
        sys.exit(2)
    return value


def _candidate_tokens() -> list[str]:
    token_names = [
        "PERSONAL_NOTION_TOKEN",
        "COMPANY_NOTION_TOKEN",
        "NOTION_TOKEN",
    ]
    tokens: list[str] = []
    for name in token_names:
        value = os.getenv(name)
        if value and value not in tokens:
            tokens.append(value)
    if not tokens:
        print("Missing env var: PERSONAL_NOTION_TOKEN, COMPANY_NOTION_TOKEN, or NOTION_TOKEN", file=sys.stderr)
        sys.exit(2)
    return tokens


def _extract_notion_id(raw: str) -> str | None:
    if not raw:
        return None

    s = (raw or "").strip()
    if not s:
        return None

    if "notion.so" in s and "/" in s:
        s = s.split("?")[0].split("/")[-1]

    m = re.search(r"([0-9a-fA-F]{32})", s)
    if m:
        raw_id = m.group(1).lower()
        return f"{raw_id[:8]}-{raw_id[8:12]}-{raw_id[12:16]}-{raw_id[16:20]}-{raw_id[20:32]}"

    m = re.search(r"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})", s)
    if m:
        return m.group(1).lower()

    return None


def _request(
    method: str,
    path: str,
    body: dict | None = None,
    params: dict | None = None,
):
    tokens = _candidate_tokens()
    if not tokens:
        print("Missing env var: PERSONAL_NOTION_TOKEN, COMPANY_NOTION_TOKEN, or NOTION_TOKEN", file=sys.stderr)
        sys.exit(2)
    token = tokens[0]
    notion_version = os.getenv("NOTION_VERSION") or DEFAULT_NOTION_VERSION

    url = f"{NOTION_API_BASE}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")

    token_errors: list[tuple[str, Exception]] = []
    for idx, token in enumerate(_candidate_tokens()):
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", f"Bearer {token}")
        req.add_header("Notion-Version", notion_version)
        req.add_header("Content-Type", "application/json")
        token_name = "NOTION_TOKEN" if token == os.getenv("NOTION_TOKEN") else (
            "COMPANY_NOTION_TOKEN" if token == os.getenv("COMPANY_NOTION_TOKEN") else "PERSONAL_NOTION_TOKEN"
        )

        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read().decode("utf-8")
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", errors="replace")
            try:
                payload = json.loads(raw)
            except Exception:
                payload = {"raw": raw}
            status = e.code
            if status in (401, 403, 404) and idx + 1 < len(_candidate_tokens()):
                token_errors.append((token_name, NotionApiError(status=status, reason=str(e.reason), payload=payload)))
                continue
            raise NotionApiError(status=status, reason=f"{str(e.reason)} ({token_name})", payload=payload)

    # Should only be reached if all tokens returned 401/403
    raise token_errors[-1][1] if token_errors else NotionApiError(status=401, reason="Notion auth failed", payload={})


def get_database(database_id: str):
    return _request("GET", f"/databases/{database_id}")

def get_page(page_id: str):
    return _request("GET", f"/pages/{page_id}")


def delete_block(block_id: str):
    return _request("DELETE", f"/blocks/{block_id}")


def clear_page_content(page_id: str):
    blocks = list_child_pages_paginated(page_id)
    for block in blocks:
        delete_block(block.get("id"))


def list_child_pages(parent_page_id: str, page_size: int = 10):
    params: dict[str, object] = {"page_size": page_size}
    return _request(
        "GET",
        f"/blocks/{parent_page_id}/children",
        params=params,
    )


def list_child_pages_paginated(parent_page_id: str, page_size: int = 100):
    items = []
    cursor = None
    while True:
        params = {"page_size": page_size}
        if cursor:
            params["start_cursor"] = cursor

        payload = _request(
            "GET",
            f"/blocks/{parent_page_id}/children",
            params=params,
        )
        items.extend(payload.get("results") or [])
        if not payload.get("has_more"):
            break
        cursor = payload.get("next_cursor")

    return items


def get_blocks_recursive(block_id: str, depth: int = 0) -> list[dict]:
    blocks = list_child_pages_paginated(block_id)
    result = []
    for block in blocks:
        result.append({"block": block, "depth": depth})
        btype = block.get("type")
        if block.get("has_children") and btype not in ("child_page", "child_database"):
            result.extend(get_blocks_recursive(block.get("id"), depth + 1))
    return result


def query_database(database_id: str, page_size: int = 10):
    return _request("POST", f"/databases/{database_id}/query", {"page_size": page_size})


def query_database_paginated(database_id: str, page_size: int = 100):
    items = []
    cursor = None
    while True:
        body = {"page_size": page_size}
        if cursor:
            body["start_cursor"] = cursor
        payload = _request("POST", f"/databases/{database_id}/query", body)
        items.extend(payload.get("results") or [])
        if not payload.get("has_more"):
            break
        cursor = payload.get("next_cursor")
    return items


def _norm_key(key: str) -> str:
    return "".join(ch for ch in key.lower().strip() if ch.isalnum())


def _find_property_by_candidates(properties: dict, candidates: list[str]) -> str | None:
    normalized = {_norm_key(k): k for k in properties.keys()}
    for candidate in candidates:
        if not candidate:
            continue
        key = _norm_key(candidate)
        if key in normalized:
            return normalized[key]
    return None


def _collect_child_databases(parent_page_id: str) -> list[dict]:
    result = []
    for block in list_child_pages_paginated(parent_page_id):
        if block.get("type") != "child_database":
            continue
        db = block.get("child_database") or {}
        title = db.get("title") or ""
        db_id = db.get("id") or block.get("id")
        result.append({
            "id": db_id,
            "title": title,
        })
    return result


def _extract_field(prop: dict) -> str:
    if not prop:
        return ""
    t = prop.get("type")
    if t == "title":
        return _first_plain_text(prop.get("title") or [])
    if t == "rich_text":
        return _first_plain_text(prop.get("rich_text") or [])
    if t == "select":
        return (prop.get("select") or {}).get("name") or ""
    if t == "status":
        return (prop.get("status") or {}).get("name") or ""
    if t == "multi_select":
        return ", ".join(item.get("name", "") for item in prop.get("multi_select") or [])
    if t == "relation":
        return ", ".join(item.get("id", "") for item in prop.get("relation") or [])
    if t == "number":
        num = prop.get("number")
        return str(num) if num is not None else ""
    if t == "checkbox":
        return "true" if prop.get("checkbox") else ""
    if t == "date":
        date = prop.get("date") or {}
        if date.get("start") and date.get("end"):
            return f"{date.get('start')}~{date.get('end')}"
        return date.get("start") or date.get("end") or ""
    return ""


def _extract_date(prop: dict) -> str | None:
    if not prop or prop.get("type") != "date":
        return None
    date = prop.get("date") or {}
    return date.get("start") or date.get("end")


def _extract_row_fields(page: dict, db: dict) -> dict:
    props = page.get("properties") or {}

    title_key = _find_property_by_candidates(props, ["이름", "제목", "name", "title", "task"])
    if not title_key:
        for name, prop in props.items():
            if (prop or {}).get("type") == "title":
                title_key = name
                break

    start_key = _find_property_by_candidates(props, ["start date", "start", "시작일", "시작", "시작날짜", "시작일자"])
    if not start_key:
        for name, prop in props.items():
            if (prop or {}).get("type") == "date":
                start_key = name
                break

    end_key = _find_property_by_candidates(props, ["end date", "end", "종료일", "종료", "종료일자", "마감일"])
    status_key = _find_property_by_candidates(props, ["status", "상태"])
    priority_key = _find_property_by_candidates(props, ["priority", "우선순위", "중요도"])
    dependency_key = _find_property_by_candidates(props, ["dependency", "dependencies", "의존성", "선행작업"])

    title = ""
    if title_key:
        prop_title = props.get(title_key) or {}
        if prop_title.get("type") == "title":
            title = _first_plain_text(prop_title.get("title") or [])
        else:
            title = _extract_field(prop_title)
    return {
        "id": page.get("id"),
        "url": page.get("url"),
        "title": title,
        "start": _extract_date(props.get(start_key) or {}),
        "end": _extract_date(props.get(end_key) or {}),
        "status": _extract_field(props.get(status_key) or {}),
        "priority": _extract_field(props.get(priority_key) or {}),
        "dependency": _extract_field(props.get(dependency_key) or {}),
    }


def _sort_rows(rows: list[dict]) -> list[dict]:
    return sorted(
        rows,
        key=lambda row: (
            row.get("start") is None,
            row.get("start") or "",
            row.get("end") is None,
            row.get("end") or "",
            row.get("status") or "",
            row.get("priority") or "",
            row.get("title") or "",
        ),
    )


def _cmd_link_workflow(args):
    target = args.notion_target
    page_id = _extract_notion_id(target)
    if not page_id:
        print("Invalid notion page URL/id.", file=sys.stderr)
        sys.exit(2)

    page = get_page(page_id)
    databases = _collect_child_databases(page_id)
    if not databases:
        print(f"No linked child database found under page {page_id}.", file=sys.stderr)
        sys.exit(3)

    rows = []
    db_meta = []
    for db in databases:
        db_id = db.get("id")
        if not db_id:
            continue
        db_obj = get_database(db_id)
        db_meta.append({"id": db_id, "title": db.get("title") or _first_plain_text(db_obj.get("title") or [])})
        for row in query_database_paginated(db_id):
            rows.append({"database_id": db_id, **_extract_row_fields(row, db_obj)})

    rows = _sort_rows(rows)
    if args.json:
        print(
            json.dumps(
                {
                    "page": {"id": page.get("id"), "url": page.get("url")},
                    "databases": db_meta,
                    "rows": rows,
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return

    print(f"Page: {page.get('id')}")
    print(f"URL: {page.get('url')}")
    print(f"Found {len(databases)} database(s), {len(rows)} row(s).")
    for db in db_meta:
        print(f"- DB: {db.get('title') or '(untitled)'} ({db.get('id')})")
    print()
    print("start\tend\tstatus\tpriority\tdependency\ttitle\turl")
    for row in rows:
        print(
            f"{row.get('start') or '미정'}\t{row.get('end') or '미정'}\t"
            f"{row.get('status') or '-'}\t{row.get('priority') or '-'}\t"
            f"{row.get('dependency') or '-'}\t{row.get('title') or '(untitled)'}\t{row.get('url') or ''}"
        )

def search_databases(query: str, page_size: int = 10):
    body = {
        "query": query,
        "page_size": page_size,
        "filter": {"value": "database", "property": "object"},
    }
    return _request("POST", "/search", body)


def search_all(
    query: str,
    filter_type: str | None = None,
    sort_direction: str = "descending",
    sort_timestamp: str = "last_edited_time",
    page_size: int = 20,
):
    """Search pages and/or databases. filter_type: 'page' | 'database' | None (both)."""
    body: dict = {"query": query, "page_size": page_size}
    if filter_type in ("page", "database"):
        body["filter"] = {"value": filter_type, "property": "object"}
    body["sort"] = {"direction": sort_direction, "timestamp": sort_timestamp}
    return _request("POST", "/search", body)


def update_page(
    page_id: str,
    title: str | None = None,
    icon_emoji: str | None = None,
    icon_url: str | None = None,
    cover_url: str | None = None,
    archived: bool | None = None,
    extra_properties: dict | None = None,
):
    """PATCH /pages/{page_id} — update title, icon, cover, or arbitrary properties."""
    payload: dict = {}

    if title is not None:
        payload.setdefault("properties", {})["title"] = {
            "title": [{"type": "text", "text": {"content": title}}]
        }

    if extra_properties:
        payload.setdefault("properties", {}).update(extra_properties)

    if icon_emoji is not None:
        payload["icon"] = {"type": "emoji", "emoji": icon_emoji}
    elif icon_url is not None:
        payload["icon"] = {"type": "external", "external": {"url": icon_url}}

    if cover_url is not None:
        payload["cover"] = {"type": "external", "external": {"url": cover_url}}

    if archived is not None:
        payload["archived"] = archived

    if not payload:
        raise ValueError("Nothing to update. Provide at least one of: --title, --icon-emoji, --icon-url, --cover-url")

    return _request("PATCH", f"/pages/{page_id}", payload)


# ── Database ──────────────────────────────────────────────────────────────────

def create_database(
    parent_page_id: str,
    title: str,
    properties: dict | None = None,
    icon_emoji: str | None = None,
    cover_url: str | None = None,
):
    """POST /databases — create a new inline database under a page."""
    payload: dict = {
        "parent": {"type": "page_id", "page_id": parent_page_id},
        "title": [{"type": "text", "text": {"content": title}}],
        "properties": properties or {"Name": {"title": {}}},
        "is_inline": True,
    }
    if icon_emoji:
        payload["icon"] = {"type": "emoji", "emoji": icon_emoji}
    if cover_url:
        payload["cover"] = {"type": "external", "external": {"url": cover_url}}
    return _request("POST", "/databases", payload)


def update_database(
    database_id: str,
    title: str | None = None,
    icon_emoji: str | None = None,
    icon_url: str | None = None,
    cover_url: str | None = None,
):
    """PATCH /databases/{id} — update title, icon, or cover of a database."""
    payload: dict = {}
    if title is not None:
        payload["title"] = [{"type": "text", "text": {"content": title}}]
    if icon_emoji is not None:
        payload["icon"] = {"type": "emoji", "emoji": icon_emoji}
    elif icon_url is not None:
        payload["icon"] = {"type": "external", "external": {"url": icon_url}}
    if cover_url is not None:
        payload["cover"] = {"type": "external", "external": {"url": cover_url}}
    if not payload:
        raise ValueError("Nothing to update.")
    return _request("PATCH", f"/databases/{database_id}", payload)


# ── Users ─────────────────────────────────────────────────────────────────────

def get_users(page_size: int = 100):
    """GET /users — list all workspace users."""
    return _request("GET", "/users", params={"page_size": page_size})


def get_me():
    """GET /users/me — retrieve the bot user for the current token."""
    return _request("GET", "/users/me")


# ── Comments ──────────────────────────────────────────────────────────────────

def add_comment(page_id: str, text: str):
    """POST /comments — add a comment to a page."""
    return _request("POST", "/comments", {
        "parent": {"page_id": page_id},
        "rich_text": [{"type": "text", "text": {"content": text}}],
    })


def get_comments(block_id: str, page_size: int = 20):
    """GET /comments — retrieve comments for a block or page."""
    return _request("GET", "/comments", params={"block_id": block_id, "page_size": page_size})


# ── File uploads ─────────────────────────────────────────────────────────────

FILE_UPLOAD_NOTION_VERSION = "2025-09-03"

_BLOCK_TYPE_BY_MIME: dict[str, str] = {
    "image/": "image",
    "video/": "video",
    "audio/": "audio",
    "application/pdf": "pdf",
}

def _guess_block_type(filename: str, content_type: str) -> str:
    for prefix, btype in _BLOCK_TYPE_BY_MIME.items():
        if content_type.startswith(prefix):
            return btype
    return "file"


def _build_multipart(file_path: str, field_name: str = "file") -> tuple[bytes, str]:
    """Build a multipart/form-data body for a single file field."""
    boundary = uuid.uuid4().hex
    filename = os.path.basename(file_path)
    content_type, _ = mimetypes.guess_type(file_path)
    content_type = content_type or "application/octet-stream"

    with open(file_path, "rb") as f:
        file_data = f.read()

    parts = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="{field_name}"; filename="{filename}"\r\n'
        f"Content-Type: {content_type}\r\n\r\n"
    ).encode("utf-8") + file_data + f"\r\n--{boundary}--\r\n".encode("utf-8")

    return parts, f"multipart/form-data; boundary={boundary}"


def _request_upload(path: str, body: bytes, content_type: str):
    """Raw HTTP POST for multipart file uploads (uses 2025-09-03 version)."""
    tokens = _candidate_tokens()
    token = tokens[0]
    url = f"{NOTION_API_BASE}{path}"
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Notion-Version", FILE_UPLOAD_NOTION_VERSION)
    req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(raw)
        except Exception:
            payload = {"raw": raw}
        raise NotionApiError(status=e.code, reason=str(e.reason), payload=payload)


def create_file_upload(filename: str, content_type: str) -> dict:
    """POST /v1/file_uploads — initialize a file upload, returns {id, status, ...}."""
    return _request(
        "POST",
        "/file_uploads",
        {"filename": filename, "content_type": content_type},
    )


def send_file_upload(file_upload_id: str, file_path: str) -> dict:
    """POST /v1/file_uploads/{id}/send — upload file bytes as multipart form."""
    body, ct = _build_multipart(file_path)
    return _request_upload(f"/file_uploads/{file_upload_id}/send", body, ct)


def attach_file_upload_to_page(
    page_id: str,
    file_upload_id: str,
    block_type: str,
    filename: str,
) -> dict:
    """Append a file_upload block to a page."""
    block: dict = {
        "object": "block",
        "type": block_type,
        block_type: {
            "type": "file_upload",
            "file_upload": {"id": file_upload_id},
        },
    }
    if block_type == "file":
        block[block_type]["name"] = filename
    return _request("PATCH", f"/blocks/{page_id}/children", {"children": [block]})


def upload_file(page_id: str, file_path: str, block_type: str | None = None) -> dict:
    """
    Full 3-step file upload:
      1. create_file_upload  2. send_file_upload  3. attach_file_upload_to_page
    Returns the append-children response.
    """
    filename = os.path.basename(file_path)
    content_type, _ = mimetypes.guess_type(file_path)
    content_type = content_type or "application/octet-stream"

    btype = block_type or _guess_block_type(filename, content_type)

    # Step 1
    upload = create_file_upload(filename, content_type)
    upload_id = upload.get("id")
    if not upload_id:
        raise RuntimeError(f"Failed to create file upload: {upload}")

    # Step 2
    send_file_upload(upload_id, file_path)

    # Step 3
    return attach_file_upload_to_page(page_id, upload_id, btype, filename)


# ── Block move ────────────────────────────────────────────────────────────────

_BLOCK_READ_ONLY_KEYS = {
    "id", "object", "created_time", "last_edited_time",
    "created_by", "last_edited_by", "has_children", "archived", "in_trash",
}

def _block_to_append_payload(block: dict) -> dict | None:
    """Strip read-only fields and return a block payload suitable for appending."""
    btype = block.get("type")
    if not btype:
        return None
    payload = {"object": "block", "type": btype}
    content = block.get(btype)
    if content is None:
        return None
    # Strip any read-only sub-keys
    if isinstance(content, dict):
        content = {k: v for k, v in content.items() if k not in _BLOCK_READ_ONLY_KEYS}
    payload[btype] = content
    return payload


def move_block(block_id: str, target_parent_id: str, after_block_id: str | None = None):
    """
    Move a block by copying it to target_parent and deleting the original.
    ⚠ child_page blocks cannot be moved — deleting them archives the page.
    """
    block = _request("GET", f"/blocks/{block_id}")
    btype = block.get("type")
    if btype == "child_page":
        raise ValueError(
            f"Block {block_id} is a child_page — moving it via API would archive the page. "
            "Use the Notion UI to drag it instead."
        )

    payload_block = _block_to_append_payload(block)
    if payload_block is None:
        raise ValueError(f"Cannot convert block type '{btype}' to append payload.")

    append_body: dict = {"children": [payload_block]}
    if after_block_id:
        append_body["after"] = after_block_id

    result = _request("PATCH", f"/blocks/{target_parent_id}/children", append_body)
    delete_block(block_id)
    return result


def _find_title_property_name(database: dict) -> str:
    props = database.get("properties") or {}
    for name, prop in props.items():
        if (prop or {}).get("type") == "title":
            return name
    print("Could not find a title property in this database.", file=sys.stderr)
    print("Tip: open the database schema and ensure it has a Title property.", file=sys.stderr)
    sys.exit(1)


def _first_plain_text(rich_text: list[dict]) -> str:
    for rt in rich_text or []:
        t = (rt or {}).get("plain_text")
        if t:
            return t
    return ""


def _extract_rich_text(rich_text_arr: list) -> str:
    return "".join((rt or {}).get("plain_text", "") for rt in rich_text_arr or [])


def _page_title(page: dict, title_prop_name: str) -> str:
    props = page.get("properties") or {}
    title_prop = props.get(title_prop_name) or {}
    title_arr = title_prop.get("title") or []
    return _first_plain_text(title_arr)


def create_page_in_database(database_id: str, title: str, content: str | None):
    db = get_database(database_id)
    title_prop_name = _find_title_property_name(db)

    properties = {
        title_prop_name: {
            "title": [{"type": "text", "text": {"content": title}}]
        }
    }

    children = []
    if content:
        children.extend(_content_to_blocks(content))

    body = {
        "parent": {"database_id": database_id},
        "properties": properties,
    }
    if children:
        body["children"] = children

    return _request("POST", "/pages", body)


def create_page_as_child(parent_page_id: str, title: str, content: str | None):
    title_prop = {"title": [{"type": "text", "text": {"content": title}}]}
    children = []
    if content:
        children.extend(_content_to_blocks(content))

    body = {
        "parent": {"page_id": parent_page_id},
        "properties": {"title": title_prop},
    }
    if children:
        body["children"] = children

    return _request("POST", "/pages", body)


def append_paragraphs(block_id: str, content: str):
    children = _content_to_blocks(content)
    return _request("PATCH", f"/blocks/{block_id}/children", {"children": children})


def _split_paragraphs(text: str) -> list[str]:
    text = text.replace("\r\n", "\n").strip("\n")
    if not text:
        return []
    parts = [p.strip() for p in text.split("\n\n")]
    out: list[str] = []
    for p in parts:
        if not p:
            continue
        # Notion has per-block text limits; keep it conservative.
        out.extend(textwrap.wrap(p, width=1800, break_long_words=False, replace_whitespace=False) or [p])
    return out


def _rt(text: str) -> list[dict]:
    """Convert text with inline markdown (**bold**, *italic*, `code`, ~~strike~~) to Notion rich_text."""
    if not text:
        return []
    return _parse_inline_markdown(text)


def _parse_inline_markdown(text: str) -> list[dict]:
    """Parse inline markdown formatting into Notion rich_text annotations."""
    # Pattern matches: **bold**, *italic*, `code`, ~~strikethrough~~
    pattern = re.compile(
        r'(\*\*(.+?)\*\*)'       # **bold**
        r'|(\*(.+?)\*)'          # *italic*
        r'|(`(.+?)`)'            # `code`
        r'|(~~(.+?)~~)'          # ~~strikethrough~~
    )

    result = []
    last_end = 0

    for m in pattern.finditer(text):
        # Add plain text before this match
        if m.start() > last_end:
            plain = text[last_end:m.start()]
            if plain:
                result.append({"type": "text", "text": {"content": plain}})

        if m.group(2) is not None:  # **bold**
            result.append({
                "type": "text",
                "text": {"content": m.group(2)},
                "annotations": {"bold": True},
            })
        elif m.group(4) is not None:  # *italic*
            result.append({
                "type": "text",
                "text": {"content": m.group(4)},
                "annotations": {"italic": True},
            })
        elif m.group(6) is not None:  # `code`
            result.append({
                "type": "text",
                "text": {"content": m.group(6)},
                "annotations": {"code": True},
            })
        elif m.group(8) is not None:  # ~~strikethrough~~
            result.append({
                "type": "text",
                "text": {"content": m.group(8)},
                "annotations": {"strikethrough": True},
            })

        last_end = m.end()

    # Add remaining plain text
    if last_end < len(text):
        remaining = text[last_end:]
        if remaining:
            result.append({"type": "text", "text": {"content": remaining}})

    # If no matches found, return plain text
    if not result:
        result.append({"type": "text", "text": {"content": text}})

    return result


def _block(block_type: str, text: str, **extra) -> dict:
    payload = {"rich_text": _rt(text)}
    payload.update(extra)
    return {"object": "block", "type": block_type, block_type: payload}


def _looks_like_markdown(text: str) -> bool:
    for line in (text or "").splitlines():
        s = line.strip()
        if not s:
            continue
        if s.startswith(("# ", "## ", "### ", "- ", "* ", "- [ ]", "- [x]", "- [X]")):
            return True
        if s.startswith("```"):
            return True
        if s.startswith("|") and "|" in s[1:]:
            return True
        if s.startswith("!["):
            return True
        if re.match(r"^\d+\.\s", s):
            return True
        if s.startswith("> "):
            return True
        if s == "---" or s == "***" or s == "___":
            return True
        return False
    return False


def _parse_table_rows(lines: list[str]) -> list[list[str]]:
    rows = []
    for line in lines:
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        rows.append(cells)
    return rows


def _is_separator_row(row: list[str]) -> bool:
    return all(re.match(r"^[-:]+$", cell.strip()) for cell in row if cell.strip())


def _table_to_blocks(rows: list[list[str]]) -> list[dict]:
    data_rows = [r for r in rows if not _is_separator_row(r)]
    if not data_rows:
        return []
    col_count = max(len(r) for r in data_rows)
    table_rows = []
    for row in data_rows:
        cells = row + [""] * (col_count - len(row))
        table_rows.append({
            "object": "block",
            "type": "table_row",
            "table_row": {
                "cells": [_rt(cell) for cell in cells],
            },
        })
    return [{
        "object": "block",
        "type": "table",
        "table": {
            "table_width": col_count,
            "has_column_header": True,
            "has_row_header": False,
            "children": table_rows,
        },
    }]


def _content_to_blocks(text: str) -> list[dict]:
    """
    Convert plain text (and Markdown subset) into Notion blocks.

    Supported:
    - Headings: #, ##, ###
    - Bullets: -, *
    - Numbered lists: 1. 2. 3.
    - Todos: - [ ], - [x]
    - Code fences: ```lang ... ```
    - Tables: | col1 | col2 |
    - Images: ![alt](url)
    - Bookmarks: [bookmark](url)  (on its own line)
    - Callouts: > [!note] text  or  > [!tip] text
    - Toggle: > [toggle] text
    - Dividers: --- or *** or ___
    - Blockquotes: > text
    Fallback: paragraphs split by blank lines.
    """
    text = (text or "").replace("\r\n", "\n")
    if not text.strip():
        return []

    if not _looks_like_markdown(text):
        return [_block("paragraph", para) for para in _split_paragraphs(text)]

    blocks: list[dict] = []
    in_code = False
    code_lang = ""
    code_lines: list[str] = []
    table_lines: list[str] = []

    def flush_code():
        nonlocal in_code, code_lang, code_lines
        if not in_code:
            return
        code = "\n".join(code_lines).rstrip("\n")
        blocks.append(
            {
                "object": "block",
                "type": "code",
                "code": {
                    "rich_text": _rt(code),
                    "language": code_lang or "plain text",
                },
            }
        )
        in_code = False
        code_lang = ""
        code_lines = []

    def flush_table():
        nonlocal table_lines
        if not table_lines:
            return
        rows = _parse_table_rows(table_lines)
        blocks.extend(_table_to_blocks(rows))
        table_lines = []

    paragraph_buf: list[str] = []

    def flush_paragraph():
        nonlocal paragraph_buf
        if not paragraph_buf:
            return
        para = "\n".join(paragraph_buf).strip("\n")
        paragraph_buf = []
        for p in _split_paragraphs(para):
            blocks.append(_block("paragraph", p))

    for raw_line in text.split("\n"):
        line = raw_line.rstrip("\n")
        s = line.strip()

        if s.startswith("```"):
            if in_code:
                flush_code()
            else:
                flush_paragraph()
                flush_table()
                in_code = True
                code_lang = s[3:].strip()
            continue

        if in_code:
            code_lines.append(line)
            continue

        # Table rows: | col | col |
        if s.startswith("|") and "|" in s[1:]:
            flush_paragraph()
            table_lines.append(s)
            continue
        elif table_lines:
            flush_table()

        if not s:
            flush_paragraph()
            continue

        # Divider: --- or *** or ___
        if s in ("---", "***", "___"):
            flush_paragraph()
            blocks.append({"object": "block", "type": "divider", "divider": {}})
            continue

        if s.startswith("# "):
            flush_paragraph()
            blocks.append(_block("heading_1", s[2:].strip()))
            continue
        if s.startswith("## "):
            flush_paragraph()
            blocks.append(_block("heading_2", s[3:].strip()))
            continue
        if s.startswith("### "):
            flush_paragraph()
            blocks.append(_block("heading_3", s[4:].strip()))
            continue

        # Image: ![alt](url)
        img_match = re.match(r"^!\[([^\]]*)\]\(([^)]+)\)$", s)
        if img_match:
            flush_paragraph()
            alt_text = img_match.group(1)
            img_url = img_match.group(2)
            blocks.append({
                "object": "block",
                "type": "image",
                "image": {
                    "type": "external",
                    "external": {"url": img_url},
                    "caption": _rt(alt_text) if alt_text else [],
                },
            })
            continue

        # Bookmark: [bookmark](url) on its own line
        bm_match = re.match(r"^\[([^\]]*)\]\((https?://[^)]+)\)$", s)
        if bm_match:
            flush_paragraph()
            bm_url = bm_match.group(2)
            caption = bm_match.group(1)
            blocks.append({
                "object": "block",
                "type": "bookmark",
                "bookmark": {
                    "url": bm_url,
                    "caption": _rt(caption) if caption else [],
                },
            })
            continue

        # Callout: > [!note] text  or  > [!tip] text
        callout_match = re.match(r"^>\s*\[!(note|tip|warning|important|info)\]\s*(.*)", s, re.IGNORECASE)
        if callout_match:
            flush_paragraph()
            callout_text = callout_match.group(2).strip()
            icon_map = {"note": "\u270f\ufe0f", "tip": "\U0001f4a1", "warning": "\u26a0\ufe0f", "important": "\u2757", "info": "\u2139\ufe0f"}
            icon = icon_map.get(callout_match.group(1).lower(), "\U0001f4a1")
            blocks.append({
                "object": "block",
                "type": "callout",
                "callout": {
                    "rich_text": _rt(callout_text),
                    "icon": {"type": "emoji", "emoji": icon},
                },
            })
            continue

        # Toggle: > [toggle] text
        toggle_match = re.match(r"^>\s*\[toggle\]\s*(.*)", s, re.IGNORECASE)
        if toggle_match:
            flush_paragraph()
            toggle_text = toggle_match.group(1).strip()
            blocks.append(_block("toggle", toggle_text))
            continue

        # Blockquote: > text
        if s.startswith("> "):
            flush_paragraph()
            blocks.append(_block("quote", s[2:].strip()))
            continue

        if s.startswith(("- [ ]", "- [x]", "- [X]")):
            flush_paragraph()
            checked = s.lower().startswith("- [x]")
            text_part = s[5:].strip()
            blocks.append(_block("to_do", text_part, checked=checked))
            continue

        if s.startswith(("- ", "* ")):
            flush_paragraph()
            blocks.append(_block("bulleted_list_item", s[2:].strip()))
            continue

        # Numbered list: 1. text
        num_match = re.match(r"^\d+\.\s+(.*)", s)
        if num_match:
            flush_paragraph()
            blocks.append(_block("numbered_list_item", num_match.group(1).strip()))
            continue

        paragraph_buf.append(line)

    flush_paragraph()
    flush_table()
    flush_code()
    return blocks


def _cmd_db_info(args):
    dbid = _extract_notion_id(args.database_id or _env("NOTION_DATABASE_ID"))
    if not dbid:
        print("Invalid database id or URL.", file=sys.stderr)
        sys.exit(2)
    try:
        db = get_database(dbid)
    except NotionApiError as e:
        payload = e.payload or {}
        if payload.get("code") == "validation_error" and "not a database" in (payload.get("message") or ""):
            print("The provided ID is a page, not a database.", file=sys.stderr)
            print("If this is a linked database view, open the original database and copy its link/ID.", file=sys.stderr)
            print("Tip: use `search-db --query <name>` to find the real database id.", file=sys.stderr)
        raise

    title_prop = _find_title_property_name(db)
    print(
        json.dumps(
            {
                "id": db.get("id"),
                "title_property": title_prop,
                "title": _first_plain_text(db.get("title") or []),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


def _cmd_page_info(args):
    pid_input = args.page_id or _env("NOTION_PAGE_ID")
    pid = _extract_notion_id(pid_input)
    if not pid:
        print("Invalid page id or page URL.", file=sys.stderr)
        print("Examples: 30e85046ff55803cbc24f142c8ebd50a or https://www.notion.so/30e85046ff55803cbc24f142c8ebd50a", file=sys.stderr)
        sys.exit(2)
    page = get_page(pid)
    print(
        json.dumps(
            {
                "id": page.get("id"),
                "object": page.get("object"),
                "url": page.get("url"),
                "parent": page.get("parent"),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


def _cmd_search_db(args):
    res = search_databases(args.query, page_size=args.limit)
    results = res.get("results") or []
    for db in results:
        dbid = db.get("id")
        title = _first_plain_text(db.get("title") or [])
        print(f"{dbid}\t{title}")


def _cmd_list(args):
    dbid = _extract_notion_id(args.database_id) if args.database_id else None
    parent_id = _extract_notion_id(args.parent_page_id) if args.parent_page_id else None

    if not dbid and not parent_id:
        dbid = _extract_notion_id(os.getenv("NOTION_DATABASE_ID"))
        parent_id = _extract_notion_id(os.getenv("NOTION_PARENT_PAGE_ID"))

    if dbid:
        if not dbid:
            print("Invalid database id or URL.", file=sys.stderr)
            sys.exit(2)
        db = get_database(dbid)
        title_prop = _find_title_property_name(db)
        res = query_database(dbid, page_size=args.limit)
        results = res.get("results") or []
        for p in results:
            pid = p.get("id")
            edited = p.get("last_edited_time")
            title = _page_title(p, title_prop)
            print(f"{pid}\t{edited}\t{title}")
        return

    if parent_id:
        parent_id = _extract_notion_id(parent_id)
        if not parent_id:
            print("Invalid parent page id or link.", file=sys.stderr)
            sys.exit(2)
        res = list_child_pages(parent_id, page_size=args.limit)
        results = res.get("results") or []
        for b in results:
            btype = b.get("type")
            if btype != "child_page":
                continue
            bid = b.get("id")
            title = (b.get("child_page") or {}).get("title", "")
            print(f"{bid}\t{title}")
        return

    print("Provide either --database-id / NOTION_DATABASE_ID or --parent-page-id / NOTION_PARENT_PAGE_ID.", file=sys.stderr)
    print("Examples: list --parent-page-id <page-id> to show child pages.", file=sys.stderr)
    sys.exit(2)


def _cmd_create(args):
    if args.content and args.content_file:
        print("Provide only one of --content or --content-file.", file=sys.stderr)
        sys.exit(2)
    content = args.content
    if args.content_file:
        with open(args.content_file, "r", encoding="utf-8") as f:
            content = f.read()

    db_id = _extract_notion_id(args.database_id) if args.database_id else None
    if args.database_id and not db_id:
        print("Invalid database id or URL.", file=sys.stderr)
        sys.exit(2)
    parent_page_id = _extract_notion_id(args.parent_page_id) if args.parent_page_id else None

    if not db_id and not parent_page_id:
        db_id = _extract_notion_id(os.getenv("NOTION_DATABASE_ID"))
        if not db_id and os.getenv("NOTION_PARENT_PAGE_ID"):
            parent_page_id = _extract_notion_id(os.getenv("NOTION_PARENT_PAGE_ID"))

    if db_id:
        page = create_page_in_database(
            db_id,
            title=args.title,
            content=content,
        )
    elif parent_page_id:
        page = create_page_as_child(
            parent_page_id,
            title=args.title,
            content=content,
        )
    else:
        print("Provide either --database-id (DB mode) or --parent-page-id (page mode).", file=sys.stderr)
        print("For page-mode, pages are created as children under the target parent page.", file=sys.stderr)
        sys.exit(2)

    if args.json:
        print(json.dumps(page, ensure_ascii=False, indent=2))
    else:
        print(page.get("id"))


def _cmd_append(args):
    if args.content and args.content_file:
        print("Provide only one of --content or --content-file.", file=sys.stderr)
        sys.exit(2)
    if not args.content and not args.content_file:
        print("Provide one of --content or --content-file.", file=sys.stderr)
        sys.exit(2)
    content = args.content
    if args.content_file:
        with open(args.content_file, "r", encoding="utf-8") as f:
            content = f.read()
    block_id = _extract_notion_id(args.block_id)
    if not block_id:
        print("Invalid block/page id or URL.", file=sys.stderr)
        sys.exit(2)
    res = append_paragraphs(block_id, content)
    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        print("ok")


def _cmd_link_append(args):
    if args.content and args.content_file:
        print("Provide only one of --content or --content-file.", file=sys.stderr)
        sys.exit(2)

    if not args.content and not args.content_file:
        print("Provide one of --content or --content-file.", file=sys.stderr)
        sys.exit(2)

    content = args.content
    if args.content_file:
        with open(args.content_file, "r", encoding="utf-8") as f:
            content = f.read()

    page_id = _extract_notion_id(args.notion_target)
    if not page_id:
        print("Invalid notion page URL/id.", file=sys.stderr)
        sys.exit(2)

    page = get_page(page_id)

    if args.dry_run:
        print(
            json.dumps(
                {
                    "preview": "append_to_page",
                    "target": {
                        "page_id": page.get("id"),
                        "url": page.get("url"),
                    },
                    "blocks_preview": _content_to_blocks(content),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return

    res = append_paragraphs(page_id, content)
    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        print(f"appended\t{page_id}")


def _block_to_text(block: dict, depth: int = 0) -> str | None:
    btype = block.get("type")
    if not btype:
        return None
    indent = "  " * depth
    content = block.get(btype) or {}
    text = _extract_rich_text(content.get("rich_text") or [])

    if btype == "paragraph":
        return f"{indent}{text}"
    if btype == "heading_1":
        return f"{indent}# {text}"
    if btype == "heading_2":
        return f"{indent}## {text}"
    if btype == "heading_3":
        return f"{indent}### {text}"
    if btype == "bulleted_list_item":
        return f"{indent}- {text}"
    if btype == "numbered_list_item":
        return f"{indent}1. {text}"
    if btype == "to_do":
        mark = "x" if content.get("checked") else " "
        return f"{indent}- [{mark}] {text}"
    if btype == "code":
        lang = content.get("language") or "plain text"
        return f"{indent}```{lang}\n{indent}{text}\n{indent}```"
    if btype in ("quote", "callout", "toggle"):
        return f"{indent}> {text}"
    if btype == "divider":
        return f"{indent}---"
    if btype == "child_page":
        return f"{indent}[Page: {content.get('title') or ''}]"
    if btype == "child_database":
        return f"{indent}[Database: {content.get('title') or ''}]"
    if btype == "image":
        img = content.get("external") or content.get("file") or {}
        caption = _extract_rich_text(content.get("caption") or [])
        return f"{indent}[Image{': ' + caption if caption else ''}: {img.get('url') or ''}]"
    if btype == "bookmark":
        caption = _extract_rich_text(content.get("caption") or [])
        return f"{indent}[Bookmark{': ' + caption if caption else ''}: {content.get('url') or ''}]"
    if btype == "embed":
        return f"{indent}[Embed: {content.get('url') or ''}]"
    if text:
        return f"{indent}{text}"
    return None


def _cmd_read_content(args):
    page_id = _extract_notion_id(args.notion_target)
    if not page_id:
        print("Invalid notion page URL/id.", file=sys.stderr)
        sys.exit(2)

    page = get_page(page_id)
    block_entries = get_blocks_recursive(page_id)

    if args.json:
        print(json.dumps(
            {"page": {"id": page.get("id"), "url": page.get("url")}, "blocks": [e["block"] for e in block_entries]},
            ensure_ascii=False, indent=2,
        ))
        return

    lines = []
    for entry in block_entries:
        line = _block_to_text(entry["block"], entry["depth"])
        if line is not None:
            lines.append(line)
    print("\n".join(lines))


def _cmd_list_blocks(args):
    page_id = _extract_notion_id(args.notion_target)
    if not page_id:
        print("Invalid notion page URL/id.", file=sys.stderr)
        sys.exit(2)

    block_entries = get_blocks_recursive(page_id)

    if args.json:
        print(json.dumps(
            [{"id": e["block"].get("id"), "type": e["block"].get("type"), "depth": e["depth"],
              "text": _block_to_text(e["block"], 0) or ""} for e in block_entries],
            ensure_ascii=False, indent=2,
        ))
        return

    for i, entry in enumerate(block_entries):
        block = entry["block"]
        bid = block.get("id", "")
        btype = block.get("type", "")
        depth = entry["depth"]
        indent = "  " * depth
        text = _block_to_text(block, 0) or ""
        # Truncate long text for display
        preview = text[:80].replace("\n", " ")
        if len(text) > 80:
            preview += "..."
        print(f"{i}\t{bid}\t{indent}{btype}\t{preview}")


def _cmd_insert_after(args):
    block_id = _extract_notion_id(args.block_id)
    if not block_id:
        print("Invalid block id.", file=sys.stderr)
        sys.exit(2)

    if args.content and args.content_file:
        print("Provide only one of --content or --content-file.", file=sys.stderr)
        sys.exit(2)
    if not args.content and not args.content_file:
        print("Provide one of --content or --content-file.", file=sys.stderr)
        sys.exit(2)

    content = args.content
    if args.content_file:
        with open(args.content_file, "r", encoding="utf-8") as f:
            content = f.read()

    children = _content_to_blocks(content)

    # Get the block's parent to insert after it
    block_info = _request("GET", f"/blocks/{block_id}")
    parent = block_info.get("parent") or {}
    parent_id = parent.get("page_id") or parent.get("block_id")
    if not parent_id:
        print("Could not determine parent of block.", file=sys.stderr)
        sys.exit(1)

    res = _request("PATCH", f"/blocks/{parent_id}/children", {
        "children": children,
        "after": block_id,
    })
    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        print(f"inserted\t{len(children)} block(s) after {block_id}")


def _cmd_delete_block(args):
    block_id = _extract_notion_id(args.block_id)
    if not block_id:
        print("Invalid block id.", file=sys.stderr)
        sys.exit(2)
    delete_block(block_id)
    print(f"deleted\t{block_id}")


def _cmd_update_block(args):
    block_id = _extract_notion_id(args.block_id)
    if not block_id:
        print("Invalid block id.", file=sys.stderr)
        sys.exit(2)

    # Get current block to know its type
    block_info = _request("GET", f"/blocks/{block_id}")
    btype = block_info.get("type")
    if not btype:
        print("Could not determine block type.", file=sys.stderr)
        sys.exit(1)

    new_text = args.text
    rich_text = _rt(new_text)

    # Build update payload based on block type
    supported_types = {
        "paragraph", "heading_1", "heading_2", "heading_3",
        "bulleted_list_item", "numbered_list_item", "quote",
        "callout", "toggle", "to_do",
    }
    if btype == "code":
        payload = {btype: {"rich_text": rich_text}}
        if args.language:
            payload[btype]["language"] = args.language
    elif btype == "to_do" and args.checked is not None:
        # --checked / --no-checked without --text
        payload = {"to_do": {"checked": args.checked}}
        if new_text:
            payload["to_do"]["rich_text"] = rich_text
    elif btype in supported_types:
        payload = {btype: {"rich_text": rich_text}}
    else:
        print(f"Updating block type '{btype}' is not supported.", file=sys.stderr)
        print(f"Supported: {', '.join(sorted(supported_types | {'code'}))}", file=sys.stderr)
        sys.exit(1)

    res = _request("PATCH", f"/blocks/{block_id}", payload)
    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        print(f"updated\t{block_id}")


def _cmd_create_db(args):
    parent_id = _extract_notion_id(args.parent_page_id)
    if not parent_id:
        print("Invalid parent page id or URL.", file=sys.stderr)
        sys.exit(2)

    # Parse --property NAME:TYPE pairs
    properties: dict = {}
    for spec in (args.property or []):
        if ":" in spec:
            name, ptype = spec.split(":", 1)
            properties[name.strip()] = {ptype.strip(): {}}
        else:
            properties[spec.strip()] = {"rich_text": {}}

    res = create_database(
        parent_id,
        title=args.title,
        properties=properties or None,
        icon_emoji=args.icon_emoji or None,
        cover_url=args.cover_url or None,
    )
    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        db_id = res.get("id", "")
        print(f"created\tdb\t{db_id}\t{args.title}")


def _cmd_update_db(args):
    db_id = _extract_notion_id(args.database_id)
    if not db_id:
        print("Invalid database id or URL.", file=sys.stderr)
        sys.exit(2)

    res = update_database(
        db_id,
        title=args.title or None,
        icon_emoji=args.icon_emoji or None,
        icon_url=args.icon_url or None,
        cover_url=args.cover_url or None,
    )
    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        updated = []
        if args.title:     updated.append(f"title={args.title!r}")
        if args.icon_emoji: updated.append(f"icon={args.icon_emoji}")
        if args.icon_url:  updated.append(f"icon_url={args.icon_url}")
        if args.cover_url: updated.append(f"cover={args.cover_url}")
        print(f"updated\tdb\t{db_id}\t{', '.join(updated)}")


def _cmd_users(args):
    if args.me:
        res = get_me()
        if args.json:
            print(json.dumps(res, ensure_ascii=False, indent=2))
        else:
            uid = res.get("id", "")
            name = res.get("name", "")
            utype = res.get("type", "")
            print(f"{uid}\t{utype}\t{name}")
        return

    res = get_users(page_size=args.limit)
    results = res.get("results") or []
    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=2))
        return
    for u in results:
        uid  = u.get("id", "")
        name = u.get("name", "")
        utype = u.get("type", "")
        email = (u.get("person") or {}).get("email", "")
        print(f"{uid}\t{utype}\t{name}\t{email}")


def _cmd_comments(args):
    if args.add:
        page_id = _extract_notion_id(args.target)
        if not page_id:
            print("Invalid page id or URL.", file=sys.stderr)
            sys.exit(2)
        res = add_comment(page_id, args.add)
        if args.json:
            print(json.dumps(res, ensure_ascii=False, indent=2))
        else:
            print(f"commented\t{page_id}")
        return

    block_id = _extract_notion_id(args.target)
    if not block_id:
        print("Invalid block/page id or URL.", file=sys.stderr)
        sys.exit(2)
    res = get_comments(block_id, page_size=args.limit)
    results = res.get("results") or []
    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=2))
        return
    for c in results:
        cid = c.get("id", "")
        created = c.get("created_time", "")[:10]
        author = ((c.get("created_by") or {}).get("name") or "unknown")
        text = _first_plain_text(c.get("rich_text") or [])
        print(f"{cid}\t{created}\t{author}\t{text}")


def _cmd_upload_file(args):
    page_id = _extract_notion_id(args.page_id)
    if not page_id:
        print("Invalid page id or URL.", file=sys.stderr)
        sys.exit(2)

    if not os.path.isfile(args.file):
        print(f"File not found: {args.file}", file=sys.stderr)
        sys.exit(2)

    filename = os.path.basename(args.file)
    file_size = os.path.getsize(args.file)
    print(f"Uploading {filename} ({file_size:,} bytes)...")

    try:
        res = upload_file(page_id, args.file, block_type=args.block_type or None)
    except NotionApiError as e:
        print(str(e), file=sys.stderr)
        print(json.dumps(e.payload, ensure_ascii=False, indent=2), file=sys.stderr)
        sys.exit(1)

    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        new_blocks = res.get("results") or []
        new_id = new_blocks[0].get("id", "") if new_blocks else ""
        print(f"uploaded\t{filename}\t→ block {new_id} on page {page_id}")


def _cmd_move_block(args):
    block_id = _extract_notion_id(args.block_id)
    if not block_id:
        print("Invalid block id.", file=sys.stderr)
        sys.exit(2)
    target_id = _extract_notion_id(args.target_parent)
    if not target_id:
        print("Invalid target parent id or URL.", file=sys.stderr)
        sys.exit(2)
    after_id = _extract_notion_id(args.after) if args.after else None

    try:
        res = move_block(block_id, target_id, after_block_id=after_id)
    except ValueError as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)

    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        dest = f"after {after_id}" if after_id else f"end of {target_id}"
        print(f"moved\t{block_id}\t→ {dest}")


def _cmd_update_page(args):
    page_id = _extract_notion_id(args.page_id)
    if not page_id:
        print("Invalid page id or URL.", file=sys.stderr)
        sys.exit(2)

    res = update_page(
        page_id,
        title=args.title or None,
        icon_emoji=args.icon_emoji or None,
        icon_url=args.icon_url or None,
        cover_url=args.cover_url or None,
        archived=args.archived if args.archived else None,
    )
    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        updated = []
        if args.title:
            updated.append(f"title={args.title!r}")
        if args.icon_emoji:
            updated.append(f"icon={args.icon_emoji}")
        if args.icon_url:
            updated.append(f"icon_url={args.icon_url}")
        if args.cover_url:
            updated.append(f"cover={args.cover_url}")
        if args.archived:
            updated.append("archived=true")
        print(f"updated\t{page_id}\t{', '.join(updated)}")


def _cmd_search(args):
    filter_type = args.type if args.type in ("page", "database") else None
    sort_dir = "ascending" if args.oldest else "descending"
    sort_ts = "created_time" if args.sort_by == "created" else "last_edited_time"

    res = search_all(
        query=args.query,
        filter_type=filter_type,
        sort_direction=sort_dir,
        sort_timestamp=sort_ts,
        page_size=args.limit,
    )

    results = res.get("results") or []
    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=2))
        return

    for obj in results:
        obj_type = obj.get("object")          # "page" or "database"
        obj_id   = obj.get("id", "")
        edited   = obj.get("last_edited_time", "")[:10]
        url      = obj.get("url", "")

        if obj_type == "database":
            title = _first_plain_text(obj.get("title") or [])
            print(f"[db]\t{obj_id}\t{edited}\t{title}")
        else:
            props = obj.get("properties") or {}
            # find title property
            title = ""
            for prop in props.values():
                if (prop or {}).get("type") == "title":
                    title = _first_plain_text(prop.get("title") or [])
                    break
            parent = obj.get("parent") or {}
            parent_type = parent.get("type", "")
            print(f"[page]\t{obj_id}\t{edited}\t{title or '(untitled)'}\t({parent_type})")


def _cmd_replace_content(args):
    if args.content and args.content_file:
        print("Provide only one of --content or --content-file.", file=sys.stderr)
        sys.exit(2)
    if not args.content and not args.content_file:
        print("Provide one of --content or --content-file.", file=sys.stderr)
        sys.exit(2)

    content = args.content
    if args.content_file:
        with open(args.content_file, "r", encoding="utf-8") as f:
            content = f.read()

    page_id = _extract_notion_id(args.notion_target)
    if not page_id:
        print("Invalid notion page URL/id.", file=sys.stderr)
        sys.exit(2)

    get_page(page_id)
    clear_page_content(page_id)
    res = append_paragraphs(page_id, content)
    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        print(f"replaced\t{page_id}")


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(
        description="Minimal Notion helper for database and page workflows using NOTION_TOKEN",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    p_db = sub.add_parser("db-info", help="Show database title property")
    p_db.add_argument("--database-id")
    p_db.set_defaults(func=_cmd_db_info)

    p_pi = sub.add_parser("page-info", help="Show basic page info")
    p_pi.add_argument("--page-id")
    p_pi.set_defaults(func=_cmd_page_info)

    p_sd = sub.add_parser("search-db", help="Search databases by name")
    p_sd.add_argument("--query", required=True)
    p_sd.add_argument("--limit", type=int, default=10)
    p_sd.set_defaults(func=_cmd_search_db)

    p_ls = sub.add_parser("list", help="List recent pages in database or child pages of a page")
    p_ls.add_argument("--database-id")
    p_ls.add_argument("--parent-page-id", help="List child pages under this page")
    p_ls.add_argument("--limit", type=int, default=10)
    p_ls.set_defaults(func=_cmd_list)

    p_cr = sub.add_parser("create", help="Create a new page (database or page child)")
    p_cr.add_argument("--database-id")
    p_cr.add_argument("--parent-page-id", help="Create a child page under this page")
    p_cr.add_argument("--title", required=True)
    p_cr.add_argument("--content")
    p_cr.add_argument("--content-file", help="Read content from a UTF-8 text file")
    p_cr.add_argument("--json", action="store_true")
    p_cr.set_defaults(func=_cmd_create)

    p_ap = sub.add_parser("append", help="Append paragraphs to a page or block")
    p_ap.add_argument("block_id", help="A page ID or block ID")
    p_ap.add_argument("--content")
    p_ap.add_argument("--content-file", help="Read content from a UTF-8 text file")
    p_ap.add_argument("--json", action="store_true")
    p_ap.set_defaults(func=_cmd_append)

    p_lw = sub.add_parser("link-workflow", help="Load a Notion page and summarize rows from linked child databases")
    p_lw.add_argument("notion_target", help="Notion page URL or page id")
    p_lw.add_argument("--json", action="store_true")
    p_lw.set_defaults(func=_cmd_link_workflow)

    p_la = sub.add_parser("link-append", help="Append text to a Notion page by page URL/id")
    p_la.add_argument("notion_target", help="Notion page URL or page id")
    p_la.add_argument("--content")
    p_la.add_argument("--content-file", help="Read content from a UTF-8 text file")
    p_la.add_argument("--dry-run", action="store_true", help="Show planned append payload without sending")
    p_la.add_argument("--json", action="store_true")
    p_la.set_defaults(func=_cmd_link_append)

    p_rc = sub.add_parser("read-content", help="Read and display all text content from a Notion page")
    p_rc.add_argument("notion_target", help="Notion page URL or page id")
    p_rc.add_argument("--json", action="store_true")
    p_rc.set_defaults(func=_cmd_read_content)

    p_lb = sub.add_parser("list-blocks", help="List all blocks in a page with their IDs")
    p_lb.add_argument("notion_target", help="Notion page URL or page id")
    p_lb.add_argument("--json", action="store_true")
    p_lb.set_defaults(func=_cmd_list_blocks)

    p_ia = sub.add_parser("insert-after", help="Insert content after a specific block")
    p_ia.add_argument("block_id", help="Block ID to insert after")
    p_ia.add_argument("--content")
    p_ia.add_argument("--content-file", help="Read content from a UTF-8 text file")
    p_ia.add_argument("--json", action="store_true")
    p_ia.set_defaults(func=_cmd_insert_after)

    p_db_del = sub.add_parser("delete-block", help="Delete a specific block by ID")
    p_db_del.add_argument("block_id", help="Block ID to delete")
    p_db_del.set_defaults(func=_cmd_delete_block)

    p_ub = sub.add_parser("update-block", help="Update a block's text content or to-do state")
    p_ub.add_argument("block_id", help="Block ID to update")
    p_ub.add_argument("--text", default="", help="New text content (supports **bold**, *italic*, `code`)")
    p_ub.add_argument("--language", help="Language for code blocks")
    p_ub.add_argument("--checked", dest="checked", action="store_true", default=None,
                      help="Mark to-do block as checked")
    p_ub.add_argument("--no-checked", dest="checked", action="store_false",
                      help="Mark to-do block as unchecked")
    p_ub.add_argument("--json", action="store_true")
    p_ub.set_defaults(func=_cmd_update_block, checked=None)

    p_cdb = sub.add_parser("create-db", help="Create a new inline database under a page")
    p_cdb.add_argument("--parent-page-id", required=True, help="Parent page URL or ID")
    p_cdb.add_argument("--title", required=True, help="Database title")
    p_cdb.add_argument("--property", action="append", metavar="NAME:TYPE",
                       help="Add a property (e.g. Status:select, Date:date). Repeatable.")
    p_cdb.add_argument("--icon-emoji", help="Emoji icon")
    p_cdb.add_argument("--cover-url", help="Cover image URL")
    p_cdb.add_argument("--json", action="store_true")
    p_cdb.set_defaults(func=_cmd_create_db)

    p_udb = sub.add_parser("update-db", help="Update database title, icon, or cover")
    p_udb.add_argument("database_id", help="Database URL or ID")
    p_udb.add_argument("--title", help="New title")
    p_udb.add_argument("--icon-emoji", help="Emoji icon")
    p_udb.add_argument("--icon-url", help="External image URL for icon")
    p_udb.add_argument("--cover-url", help="Cover image URL")
    p_udb.add_argument("--json", action="store_true")
    p_udb.set_defaults(func=_cmd_update_db)

    p_usr = sub.add_parser("users", help="List workspace users or show current bot user")
    p_usr.add_argument("--me", action="store_true", help="Show the bot user for current token")
    p_usr.add_argument("--limit", type=int, default=100)
    p_usr.add_argument("--json", action="store_true")
    p_usr.set_defaults(func=_cmd_users)

    p_cmt = sub.add_parser("comments", help="Add or list comments on a page/block")
    p_cmt.add_argument("target", help="Page or block URL/ID")
    p_cmt.add_argument("--add", metavar="TEXT", help="Add a new comment with this text")
    p_cmt.add_argument("--limit", type=int, default=20)
    p_cmt.add_argument("--json", action="store_true")
    p_cmt.set_defaults(func=_cmd_comments)

    p_uf = sub.add_parser("upload-file", help="Upload a local file to a Notion page (image/video/audio/pdf/file)")
    p_uf.add_argument("page_id", help="Target page URL or ID")
    p_uf.add_argument("--file", required=True, help="Path to the local file to upload")
    p_uf.add_argument("--block-type", choices=["image", "video", "audio", "pdf", "file"],
                      help="Force a specific block type (default: auto-detect from file extension)")
    p_uf.add_argument("--json", action="store_true")
    p_uf.set_defaults(func=_cmd_upload_file)

    p_mv = sub.add_parser("move-block", help="Move a block to a different parent page/block")
    p_mv.add_argument("block_id", help="Block ID to move")
    p_mv.add_argument("target_parent", help="Target parent page or block URL/ID")
    p_mv.add_argument("--after", metavar="BLOCK_ID",
                      help="Insert after this block in the target (default: append to end)")
    p_mv.add_argument("--json", action="store_true")
    p_mv.set_defaults(func=_cmd_move_block)

    p_up = sub.add_parser("update-page", help="Update page title, icon, or cover")
    p_up.add_argument("page_id", help="Page URL or page ID")
    p_up.add_argument("--title", help="New page title")
    p_up.add_argument("--icon-emoji", help="Emoji icon (e.g. 🧠)")
    p_up.add_argument("--icon-url", help="External image URL for icon")
    p_up.add_argument("--cover-url", help="External image URL for cover")
    p_up.add_argument("--archived", action="store_true", help="Archive (trash) the page")
    p_up.add_argument("--json", action="store_true")
    p_up.set_defaults(func=_cmd_update_page)

    p_s = sub.add_parser("search", help="Search pages and databases by title")
    p_s.add_argument("query", help="Search query string")
    p_s.add_argument("--type", choices=["page", "database"], help="Filter by object type (default: both)")
    p_s.add_argument("--sort-by", choices=["edited", "created"], default="edited", help="Sort by last_edited_time or created_time (default: edited)")
    p_s.add_argument("--oldest", action="store_true", help="Sort ascending (oldest first)")
    p_s.add_argument("--limit", type=int, default=20)
    p_s.add_argument("--json", action="store_true")
    p_s.set_defaults(func=_cmd_search)

    p_rp = sub.add_parser("replace-content", help="Replace all content of a Notion page")
    p_rp.add_argument("notion_target", help="Notion page URL or page id")
    p_rp.add_argument("--content")
    p_rp.add_argument("--content-file", help="Read content from a UTF-8 text file")
    p_rp.add_argument("--json", action="store_true")
    p_rp.set_defaults(func=_cmd_replace_content)

    args = p.parse_args(argv)
    try:
        args.func(args)
    except NotionApiError as e:
        print(str(e), file=sys.stderr)
        print(json.dumps(e.payload, ensure_ascii=False, indent=2), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
