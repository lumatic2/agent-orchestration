from __future__ import annotations

import re
import subprocess
import threading
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from flask import Flask, jsonify, render_template, request

app = Flask(__name__)

REPO_ROOT = Path(__file__).resolve().parent.parent
SCHEDULE_PATH = REPO_ROOT / "SCHEDULE.md"

SECTION_TITLE = {
    "today": "## 오늘 (Today)",
    "deadline": "## 마감 있음 (Deadline)",
    "anytime": "## 언제든 (Anytime)",
}
SECTION_LABEL = {v: k for k, v in SECTION_TITLE.items()}
CATEGORY_ORDER = ["#회사", "#개발", "#학습", "#크리에이티브", "#라이프", "#노션"]
PRIORITIES = ["높", "중", "낮", "-"]
STATUS_CYCLE = [" ", "/", "x"]
TASK_RE = re.compile(r"^- \[( |/|x)\] \[(높|중|낮|-)\] (.+)$")
TAG_RE = re.compile(r"#[\w가-힣]+")
BACKTICK_RE = re.compile(r"`([^`]+)`")
HEADING_RE = re.compile(r"^#{3,4}\s+")

write_lock = threading.Lock()


@dataclass
class Task:
    id: int
    line_index: int
    section: str
    category: str | None
    status: str
    priority: str
    content: str
    deadline: str | None
    tags: list[str]


def run_git(args: list[str]) -> tuple[bool, str]:
    proc = subprocess.run(
        ["git", *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    output = (proc.stdout or "") + (proc.stderr or "")
    return proc.returncode == 0, output.strip()


def git_pull() -> dict[str, Any]:
    ok, output = run_git(["pull", "--rebase"])
    return {"ok": ok, "output": output}


def git_commit_push() -> dict[str, Any]:
    add_ok, add_out = run_git(["add", str(SCHEDULE_PATH)])
    if not add_ok:
        return {"ok": False, "step": "add", "output": add_out}

    commit_ok, commit_out = run_git(["commit", "-m", "dashboard: update"])
    if not commit_ok:
        if "nothing to commit" in commit_out.lower() or "nothing added to commit" in commit_out.lower():
            return {"ok": True, "step": "commit", "output": commit_out}
        return {"ok": False, "step": "commit", "output": commit_out}

    push_ok, push_out = run_git(["push"])
    return {"ok": push_ok, "step": "push", "output": push_out}


def read_lines() -> list[str]:
    return SCHEDULE_PATH.read_text(encoding="utf-8").splitlines()


def write_lines(lines: list[str]) -> None:
    SCHEDULE_PATH.write_text("\n".join(lines).rstrip("\n") + "\n", encoding="utf-8")


def extract_deadline(text: str) -> tuple[str, str | None]:
    deadline = None

    def repl(match: re.Match[str]) -> str:
        nonlocal deadline
        raw = match.group(1).strip()
        if raw:
            value = raw[3:].strip() if raw.startswith("마감:") else raw
            if deadline is None and value:
                deadline = value
        return ""

    cleaned = BACKTICK_RE.sub(repl, text)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned, deadline


def strip_tags(text: str) -> tuple[str, list[str]]:
    tags = TAG_RE.findall(text)
    without = TAG_RE.sub("", text)
    without = re.sub(r"\s+", " ", without).strip()
    return without, tags


def extract_category(tags: list[str], fallback: str | None) -> str | None:
    for tag in tags:
        if tag in CATEGORY_ORDER:
            return tag
    return fallback


def parse_tasks(lines: list[str]) -> list[Task]:
    tasks: list[Task] = []
    section: str | None = None
    category_hint: str | None = None

    for i, line in enumerate(lines):
        line = line.rstrip()
        if line.startswith("## "):
            section = SECTION_LABEL.get(line)
            category_hint = None
            continue

        if section and HEADING_RE.match(line):
            match_cat = None
            for cat in CATEGORY_ORDER:
                if cat in line:
                    match_cat = cat
                    break
            if match_cat:
                category_hint = match_cat

        m = TASK_RE.match(line)
        if not m or not section:
            continue

        status, priority, body = m.groups()
        without_deadline, deadline = extract_deadline(body)
        content, tags = strip_tags(without_deadline)
        category = extract_category(tags, category_hint)
        keep_tags = [t for t in tags if t != category]

        tasks.append(
            Task(
                id=i,
                line_index=i,
                section=section,
                category=category,
                status=status,
                priority=priority,
                content=content,
                deadline=deadline,
                tags=keep_tags,
            )
        )

    return tasks


def build_task_line(task: Task) -> str:
    base = f"- [{task.status}] [{task.priority}] {task.content.strip()}"
    if task.deadline:
        base += f" `마감: {task.deadline.strip()}`"

    tags: list[str] = []
    if task.category:
        tags.append(task.category)
    for tag in task.tags:
        if tag not in tags:
            tags.append(tag)
    if tags:
        base += " " + " ".join(tags)

    return base.rstrip()


def find_section_bounds(lines: list[str], section_key: str) -> tuple[int, int]:
    title = SECTION_TITLE[section_key]
    start = -1

    for idx, line in enumerate(lines):
        if line.strip() == title:
            start = idx
            break
    if start == -1:
        raise ValueError(f"Section not found: {section_key}")

    end = len(lines)
    for idx in range(start + 1, len(lines)):
        if lines[idx].startswith("## "):
            end = idx
            break

    return start, end


def find_insert_index(lines: list[str], section_key: str, category: str | None) -> int:
    start, end = find_section_bounds(lines, section_key)

    if category:
        heading_idx = -1
        for idx in range(start + 1, end):
            if HEADING_RE.match(lines[idx]) and category in lines[idx]:
                heading_idx = idx
                break

        if heading_idx != -1:
            insert_at = heading_idx + 1
            for idx in range(heading_idx + 1, end):
                if HEADING_RE.match(lines[idx]):
                    return idx
                insert_at = idx + 1
            return insert_at

    insert_at = end
    while insert_at > start + 1 and not lines[insert_at - 1].strip():
        insert_at -= 1
    return insert_at


def task_to_dict(task: Task) -> dict[str, Any]:
    return {
        "id": str(task.id),
        "section": task.section,
        "category": task.category,
        "status": task.status,
        "priority": task.priority,
        "content": task.content,
        "deadline": task.deadline,
        "tags": task.tags,
    }


def load_tasks() -> list[Task]:
    return parse_tasks(read_lines())


def find_task_by_id(tasks: list[Task], task_id: str) -> Task:
    try:
        line_id = int(task_id)
    except ValueError as exc:
        raise KeyError("Invalid task id") from exc

    for task in tasks:
        if task.id == line_id:
            return task
    raise KeyError("Task not found")


def cycle_status(status: str) -> str:
    try:
        idx = STATUS_CYCLE.index(status)
    except ValueError:
        idx = 0
    return STATUS_CYCLE[(idx + 1) % len(STATUS_CYCLE)]


def apply_write_and_sync(lines: list[str]) -> dict[str, Any]:
    write_lines(lines)
    return git_commit_push()


@app.get("/")
def index() -> str:
    return render_template("index.html")


@app.get("/api/tasks")
def api_tasks():
    tasks = [task_to_dict(t) for t in load_tasks()]
    return jsonify({"tasks": tasks, "updated_at": datetime.now().isoformat(timespec="seconds")})


@app.post("/api/tasks")
def api_add_task():
    data = request.get_json(silent=True) or {}
    section = data.get("section", "today")
    if section not in SECTION_TITLE:
        return jsonify({"ok": False, "error": "Invalid section"}), 400

    priority = data.get("priority", "-")
    if priority not in PRIORITIES:
        priority = "-"

    content = (data.get("content") or "").strip()
    if not content:
        return jsonify({"ok": False, "error": "content is required"}), 400

    deadline = (data.get("deadline") or "").strip() or None
    category = (data.get("category") or "").strip() or None
    if category and category not in CATEGORY_ORDER:
        category = None

    extra_tags = [tag for tag in data.get("tags", []) if isinstance(tag, str)]

    new_task = Task(
        id=-1,
        line_index=-1,
        section=section,
        category=category,
        status=" ",
        priority=priority,
        content=content,
        deadline=deadline,
        tags=extra_tags,
    )

    with write_lock:
        lines = read_lines()
        insert_at = find_insert_index(lines, section, category)
        lines.insert(insert_at, build_task_line(new_task))
        sync_result = apply_write_and_sync(lines)

    tasks = [task_to_dict(t) for t in load_tasks()]
    return jsonify({"ok": True, "sync": sync_result, "tasks": tasks})


@app.put("/api/tasks/<task_id>")
def api_update_task(task_id: str):
    payload = request.get_json(silent=True) or {}

    with write_lock:
        lines = read_lines()
        tasks = parse_tasks(lines)
        try:
            task = find_task_by_id(tasks, task_id)
        except KeyError as exc:
            return jsonify({"ok": False, "error": str(exc)}), 404

        if payload.get("action") == "toggle":
            task.status = cycle_status(task.status)
        else:
            if "status" in payload and payload["status"] in STATUS_CYCLE:
                task.status = payload["status"]
            if "priority" in payload and payload["priority"] in PRIORITIES:
                task.priority = payload["priority"]
            if "content" in payload:
                content = str(payload["content"]).strip()
                if content:
                    task.content = content
            if "deadline" in payload:
                deadline_value = str(payload["deadline"]).strip()
                task.deadline = deadline_value or None
            if "category" in payload:
                category = str(payload["category"]).strip() or None
                if category in CATEGORY_ORDER or category is None:
                    task.category = category
            if "tags" in payload and isinstance(payload["tags"], list):
                task.tags = [str(t) for t in payload["tags"] if isinstance(t, str)]

        lines[task.line_index] = build_task_line(task)
        sync_result = apply_write_and_sync(lines)

    tasks_now = [task_to_dict(t) for t in load_tasks()]
    return jsonify({"ok": True, "sync": sync_result, "tasks": tasks_now})


@app.delete("/api/tasks/<task_id>")
def api_delete_task(task_id: str):
    with write_lock:
        lines = read_lines()
        tasks = parse_tasks(lines)
        try:
            task = find_task_by_id(tasks, task_id)
        except KeyError as exc:
            return jsonify({"ok": False, "error": str(exc)}), 404

        lines.pop(task.line_index)
        sync_result = apply_write_and_sync(lines)

    tasks_now = [task_to_dict(t) for t in load_tasks()]
    return jsonify({"ok": True, "sync": sync_result, "tasks": tasks_now})


@app.route("/api/sync", methods=["GET", "POST"])
def api_sync():
    result = git_pull()
    return jsonify(result), (200 if result["ok"] else 500)


def startup_sync() -> None:
    result = git_pull()
    state = "OK" if result["ok"] else "FAIL"
    print(f"[startup git pull] {state}: {result['output']}")


if __name__ == "__main__":
    startup_sync()
    app.run(host="0.0.0.0", port=5050, debug=False)
