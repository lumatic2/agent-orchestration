from __future__ import annotations

from dataclasses import dataclass
from difflib import SequenceMatcher


_ALLOWED_SOURCES = {"arxiv", "semantic_scholar", "openalex", "pubmed"}


@dataclass
class Paper:
    title: str
    authors: list[str]
    year: int | None
    url: str
    doi: str | None
    abstract: str
    source: str
    pmid: str | None = None

    def __post_init__(self) -> None:
        if self.source not in _ALLOWED_SOURCES:
            raise ValueError(f"Invalid source: {self.source}")

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Paper):
            return False

        self_doi = (self.doi or "").strip().lower()
        other_doi = (other.doi or "").strip().lower()
        if self_doi and other_doi:
            return self_doi == other_doi

        left = self.title.strip().lower()
        right = other.title.strip().lower()
        return SequenceMatcher(None, left, right).ratio() >= 0.85

    def to_markdown(self) -> str:
        authors = ", ".join(self.authors) if self.authors else "Unknown"
        year = str(self.year) if self.year is not None else "n.d."
        parts = [f"- **{self.title}** ({year})", f"  - Authors: {authors}", f"  - Source: {self.source}"]
        if self.doi:
            parts.append(f"  - DOI: {self.doi}")
        if self.pmid:
            parts.append(f"  - PMID: {self.pmid}")
        if self.url:
            parts.append(f"  - URL: {self.url}")
        if self.abstract:
            parts.append(f"  - Abstract: {self.abstract}")
        return "\n".join(parts)
