from __future__ import annotations

from pipeline.models.paper import Paper


def test_paper_creation() -> None:
    paper = Paper(
        title="A Paper",
        authors=["Alice", "Bob"],
        year=2024,
        url="https://example.org/paper",
        doi="10.1000/xyz",
        abstract="Summary",
        source="arxiv",
        pmid="12345",
    )

    assert paper.title == "A Paper"
    assert paper.authors == ["Alice", "Bob"]
    assert paper.year == 2024
    assert paper.url == "https://example.org/paper"
    assert paper.doi == "10.1000/xyz"
    assert paper.abstract == "Summary"
    assert paper.source == "arxiv"
    assert paper.pmid == "12345"


def test_paper_eq_same_doi() -> None:
    left = Paper("Title A", ["A"], 2020, "", "10.1/abc", "", "arxiv")
    right = Paper("Different", ["B"], 2021, "", "10.1/ABC", "", "arxiv")
    assert left == right


def test_paper_eq_similar_title() -> None:
    left = Paper("A Study on AI Systems", ["A"], 2020, "", None, "", "arxiv")
    right = Paper("A Study on AI System", ["B"], 2021, "", None, "", "arxiv")
    assert left == right


def test_paper_eq_different() -> None:
    left = Paper("Graph Models", ["A"], 2020, "", "10.1/a", "", "arxiv")
    right = Paper("Language Models", ["B"], 2021, "", "10.1/b", "", "arxiv")
    assert left != right


def test_paper_to_markdown() -> None:
    paper = Paper("A Paper", ["Alice", "Bob"], 2024, "https://x", "10.1000/xyz", "Text", "arxiv")
    markdown = paper.to_markdown()
    assert "**A Paper**" in markdown
    assert "Authors: Alice, Bob" in markdown
    assert "DOI: 10.1000/xyz" in markdown
