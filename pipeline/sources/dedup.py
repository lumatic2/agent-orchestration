from __future__ import annotations

from pipeline.models.paper import Paper


def deduplicate(papers: list[Paper]) -> list[Paper]:
    unique: list[Paper] = []
    for paper in papers:
        if any(paper == existing for existing in unique):
            continue
        unique.append(paper)
    return unique
