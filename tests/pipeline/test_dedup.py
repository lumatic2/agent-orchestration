from __future__ import annotations

from pipeline.models.paper import Paper
from pipeline.sources.dedup import deduplicate


def test_dedup_by_doi() -> None:
    papers = [
        Paper("A", ["x"], 2020, "", "10.1/a", "", "arxiv"),
        Paper("B", ["y"], 2021, "", "10.1/a", "", "arxiv"),
        Paper("C", ["z"], 2022, "", "10.1/c", "", "arxiv"),
    ]
    deduped = deduplicate(papers)
    assert len(deduped) == 2


def test_dedup_by_title() -> None:
    papers = [
        Paper("A Study on AI Systems", ["x"], 2020, "", None, "", "arxiv"),
        Paper("A Study on AI System", ["y"], 2021, "", None, "", "arxiv"),
        Paper("Different Topic", ["z"], 2022, "", None, "", "arxiv"),
    ]
    deduped = deduplicate(papers)
    assert len(deduped) == 2


def test_dedup_preserves_order() -> None:
    first = Paper("Same DOI First", ["x"], 2020, "", "10.1/a", "", "arxiv")
    duplicate = Paper("Same DOI Second", ["y"], 2021, "", "10.1/a", "", "arxiv")
    third = Paper("Unique", ["z"], 2022, "", "10.1/c", "", "arxiv")
    deduped = deduplicate([first, duplicate, third])
    assert deduped == [first, third]


def test_dedup_empty() -> None:
    assert deduplicate([]) == []
