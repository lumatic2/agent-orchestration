#!/usr/bin/env python3
# env.sh path reference: C:/Users/1/projects/agent-orchestration/scripts/env.sh
"""
Extract task-relevant Markdown context from an Understand-Anything knowledge graph.

Usage:
  python3 scripts/ua_context.py <project_dir> <task_text> [--tier medium|high|ultra] [--max-tokens 2000]
"""

import argparse
import hashlib
import json
import os
import re
import sys
import time


TIER_LIMITS = {
    "medium": 10,
    "high": 20,
    "ultra": 30,
}

TIER_HOPS = {
    "medium": 0,
    "high": 1,
    "ultra": 2,
}

PATH_PATTERN = re.compile(
    r"(?<![\w./\\-])(?:[A-Za-z0-9_.-]+[\\/])+[A-Za-z0-9_.-]+\.[A-Za-z0-9_.-]+"
)
BARE_FILE_PATTERN = re.compile(
    r"(?<![A-Za-z0-9_/\\-])[A-Za-z0-9_-]+\.(?:py|sh|ts|js|yaml|yml|json|toml|md|rs|go)(?![A-Za-z0-9_.])"
)
SNAKE_PATTERN = re.compile(r"\b[a-z][a-z0-9]*_[a-z0-9_]+\b")
CAMEL_PATTERN = re.compile(r"\b[a-z]+(?:[A-Z][A-Za-z0-9]*)+\b")
PASCAL_PATTERN = re.compile(r"\b[A-Z][A-Za-z0-9]+(?:[A-Z][A-Za-z0-9]*)*\b")
KOREAN_PATTERN = re.compile(r"[\u3131-\u318E\uAC00-\uD7A3]")


def warn(message):
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    sys.stderr.write("[ua_context][WARN][%s] %s\n" % (timestamp, message))


def configure_stdio():
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if callable(reconfigure):
            reconfigure(encoding="utf-8", errors="replace")


def normalize_text(value):
    if value is None:
        return ""
    return re.sub(r"\s+", " ", str(value)).strip()


def normalize_path(value):
    return normalize_text(value).replace("\\", "/")


def stable_hash(*parts):
    source = "|".join([str(part) for part in parts])
    return hashlib.sha1(source.encode("utf-8", errors="ignore")).hexdigest()


def unique_ordered(values):
    seen = {}
    output = []
    for value in values:
        text = normalize_text(value)
        if not text:
            continue
        if text in seen:
            continue
        seen[text] = True
        output.append(text)
    return output


def load_knowledge_graph(project_dir):
    kg_path = os.path.join(project_dir, ".understand-anything", "knowledge-graph.json")
    if not os.path.exists(kg_path):
        warn("knowledge graph not found: %s" % kg_path)
        return None

    try:
        with open(kg_path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except Exception as exc:
        warn("failed to parse knowledge graph: %s" % exc)
        return None


def add_keyword(bucket, term, weight):
    normalized = normalize_path(term).strip()
    if not normalized:
        return
    if KOREAN_PATTERN.search(normalized):
        return
    if not re.search(r"[A-Za-z]", normalized):
        return

    key = normalized.lower()
    existing = bucket.get(key)
    if existing is None or weight > existing["weight"]:
        bucket[key] = {"term": key, "weight": weight}


def extract_keywords(task_text):
    keywords = {}
    text = task_text or ""

    for path in PATH_PATTERN.findall(text):
        normalized_path = normalize_path(path)
        add_keyword(keywords, normalized_path, 12)

        base = os.path.basename(normalized_path)
        if base:
            add_keyword(keywords, base, 9)
            stem = base.rsplit(".", 1)[0] if "." in base else base
            add_keyword(keywords, stem, 7)

    for bare_file in BARE_FILE_PATTERN.findall(text):
        add_keyword(keywords, bare_file, 10)
        stem = bare_file.rsplit(".", 1)[0]
        add_keyword(keywords, stem, 7)

    english_text = KOREAN_PATTERN.sub(" ", text)
    for pattern in (SNAKE_PATTERN, CAMEL_PATTERN, PASCAL_PATTERN):
        for identifier in pattern.findall(english_text):
            add_keyword(keywords, identifier, 8)

    ordered = sorted(
        keywords.values(),
        key=lambda item: (-item["weight"], -len(item["term"]), item["term"]),
    )
    return ordered


def build_indexes(kg):
    node_by_id = {}
    outgoing = {}
    incoming = {}
    neighbors = {}
    layer_by_node = {}

    for node in (kg.get("nodes") or []):
        node_id = normalize_text(node.get("id", ""))
        if not node_id:
            continue
        node_by_id[node_id] = node
        outgoing[node_id] = []
        incoming[node_id] = []
        neighbors[node_id] = []

    for edge in (kg.get("edges") or []):
        source = normalize_text(edge.get("source", ""))
        target = normalize_text(edge.get("target", ""))
        if source not in node_by_id or target not in node_by_id:
            continue
        outgoing[source].append(target)
        incoming[target].append(source)
        neighbors[source].append(target)
        neighbors[target].append(source)

    for layer in (kg.get("layers") or []):
        layer_name = normalize_text(layer.get("name", "")) or "Unknown"
        for raw_node_id in (layer.get("nodeIds") or []):
            node_id = normalize_text(raw_node_id)
            if not node_id:
                continue
            layer_by_node.setdefault(node_id, []).append(layer_name)

    for node_id in neighbors:
        neighbors[node_id] = unique_ordered(neighbors[node_id])
    for node_id in outgoing:
        outgoing[node_id] = unique_ordered(outgoing[node_id])
    for node_id in incoming:
        incoming[node_id] = unique_ordered(incoming[node_id])
    for node_id in layer_by_node:
        layer_by_node[node_id] = unique_ordered(layer_by_node[node_id])

    return {
        "node_by_id": node_by_id,
        "outgoing": outgoing,
        "incoming": incoming,
        "neighbors": neighbors,
        "layer_by_node": layer_by_node,
    }


def score_node(node, keywords):
    name = normalize_text(node.get("name", "")).lower()
    file_path = normalize_path(node.get("filePath", "")).lower()
    summary = normalize_text(node.get("summary", "")).lower()
    tags = [normalize_text(tag).lower() for tag in (node.get("tags") or [])]
    tags_blob = " ".join(tags)

    score = 0
    for keyword in keywords:
        term = keyword["term"]
        weight = keyword["weight"]

        if file_path and term in file_path:
            score += weight * 5
            if term == file_path:
                score += weight * 3

        if name and term in name:
            score += weight * 4
            if term == name:
                score += weight * 2

        if tags_blob and term in tags_blob:
            score += weight * 3

        if summary and term in summary:
            score += max(1, weight // 2)

    return score


def sort_direct_matches(node_ids, score_map, node_by_id):
    return sorted(
        node_ids,
        key=lambda node_id: (
            -score_map.get(node_id, 0),
            normalize_path(node_by_id[node_id].get("filePath", "")).lower(),
            normalize_text(node_by_id[node_id].get("name", "")).lower(),
            stable_hash(node_id),
        ),
    )


def expand_matches(direct_ids, tier, neighbors, score_map):
    limit = TIER_LIMITS[tier]
    hops = TIER_HOPS[tier]

    if not direct_ids:
        return []

    selected = list(direct_ids[:limit])
    if hops == 0 or len(selected) >= limit:
        return selected

    visited = {}
    frontier = []
    depth_map = {}

    for node_id in selected:
        visited[node_id] = True
        frontier.append(node_id)
        depth_map[node_id] = 0

    discovered = []
    current_hop = 0
    while frontier and current_hop < hops:
        current_hop += 1
        next_frontier = []
        for node_id in frontier:
            for neighbor in (neighbors.get(node_id) or []):
                if neighbor in visited:
                    continue
                visited[neighbor] = True
                depth_map[neighbor] = current_hop
                discovered.append(neighbor)
                next_frontier.append(neighbor)
        frontier = next_frontier

    discovered.sort(
        key=lambda node_id: (
            depth_map.get(node_id, 99),
            -score_map.get(node_id, 0),
            stable_hash(node_id),
        )
    )

    for node_id in discovered:
        if len(selected) >= limit:
            break
        selected.append(node_id)

    return selected


def node_label(node):
    file_path = normalize_path(node.get("filePath", ""))
    if file_path:
        return file_path
    name = normalize_text(node.get("name", ""))
    if name:
        return name
    return "-"


def format_refs(labels, limit):
    values = unique_ordered(labels)
    if not values:
        return "-"
    clipped = values[:limit]
    return ", ".join(["`%s`" % value for value in clipped])


def format_component(node_id, indexes):
    node = indexes["node_by_id"][node_id]

    file_path = normalize_path(node.get("filePath", "")) or node_label(node)
    layers = indexes["layer_by_node"].get(node_id, [])
    layer_name = ", ".join(layers) if layers else "Unknown"
    summary = normalize_text(node.get("summary", "")) or "-"

    depends = []
    for dep_id in indexes["outgoing"].get(node_id, []):
        dep_node = indexes["node_by_id"].get(dep_id, {})
        depends.append(node_label(dep_node))

    used_by = []
    for user_id in indexes["incoming"].get(node_id, []):
        user_node = indexes["node_by_id"].get(user_id, {})
        used_by.append(node_label(user_node))

    lines = [
        "- `%s` (%s) — %s" % (file_path, layer_name, summary),
        "  → depends: %s" % format_refs(depends, 5),
        "  → used by: %s" % format_refs(used_by, 5),
    ]
    return "\n".join(lines)


def relevant_layer_lines(selected_ids, kg):
    selected = {}
    for node_id in selected_ids:
        selected[node_id] = True

    lines = []
    for layer in (kg.get("layers") or []):
        node_ids = [normalize_text(node_id) for node_id in (layer.get("nodeIds") or [])]
        if not any(node_id in selected for node_id in node_ids):
            continue
        name = normalize_text(layer.get("name", "")) or "Unknown"
        description = normalize_text(layer.get("description", "")) or "-"
        lines.append("- %s: %s" % (name, description))
    return lines


def append_block(output, block, max_chars):
    candidate = block if not output else output + "\n" + block
    if len(candidate) > max_chars:
        return output, False
    return candidate, True


def render_markdown(kg, selected_ids, indexes, max_tokens):
    max_chars = max(0, int(max_tokens) * 4)
    if max_chars == 0:
        return ""

    project = kg.get("project") or {}
    project_name = normalize_text(project.get("name", "")) or "Unknown"
    languages = ", ".join(
        [normalize_text(value) for value in (project.get("languages") or []) if normalize_text(value)]
    )
    frameworks = ", ".join(
        [normalize_text(value) for value in (project.get("frameworks") or []) if normalize_text(value)]
    )
    languages = languages or "-"
    frameworks = frameworks or "-"

    output = ""
    opening_blocks = [
        "## Codebase Context (from knowledge graph)",
        "**Project**: %s | **Stack**: %s, %s" % (project_name, languages, frameworks),
        "",
        "### Relevant Components",
    ]
    for block in opening_blocks:
        output, ok = append_block(output, block, max_chars)
        if not ok:
            return output.rstrip()

    for node_id in selected_ids:
        component = format_component(node_id, indexes)
        output, ok = append_block(output, component, max_chars)
        if not ok:
            break

    arch_lines = relevant_layer_lines(selected_ids, kg)
    output, ok = append_block(output, "", max_chars)
    if not ok:
        return output.rstrip()
    output, ok = append_block(output, "### Architecture Notes", max_chars)
    if not ok:
        return output.rstrip()

    for line in arch_lines:
        output, ok = append_block(output, line, max_chars)
        if not ok:
            break

    return output.rstrip()


def main():
    parser = argparse.ArgumentParser(
        description="Extract task-relevant Markdown context from an Understand-Anything knowledge graph."
    )
    parser.add_argument("project_dir")
    parser.add_argument("task_text")
    parser.add_argument("--tier", choices=["medium", "high", "ultra"], default="medium")
    parser.add_argument("--max-tokens", type=int, default=2000)
    args = parser.parse_args()

    try:
        configure_stdio()
        kg = load_knowledge_graph(args.project_dir)
        if not kg:
            return 0

        keywords = extract_keywords(args.task_text)
        if not keywords:
            return 0

        indexes = build_indexes(kg)
        node_by_id = indexes["node_by_id"]

        score_map = {}
        for node_id, node in node_by_id.items():
            score = score_node(node, keywords)
            if score > 0:
                score_map[node_id] = score

        if not score_map:
            return 0

        direct_ids = sort_direct_matches(list(score_map.keys()), score_map, node_by_id)
        selected_ids = expand_matches(direct_ids, args.tier, indexes["neighbors"], score_map)
        if not selected_ids:
            return 0

        markdown = render_markdown(kg, selected_ids, indexes, args.max_tokens)
        if not markdown:
            return 0

        sys.stdout.write(markdown)
        if not markdown.endswith("\n"):
            sys.stdout.write("\n")
        return 0
    except Exception as exc:
        warn("unexpected error: %s" % exc)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
