from __future__ import annotations

import re

from pipeline.core.file_ops import atomic_write, safe_read
from pipeline.models.stage_result import StageResult
from pipeline.stages.base import Stage, StageContext
from pipeline.vault.ssh_sync import VaultSync


SECTION_PATTERN = re.compile(
    r"SECTION_ADDITION\[(.+?)\]\n(.*?)(?=SECTION_ADDITION|\Z)",
    flags=re.DOTALL,
)


def _merge_section_additions(draft: str, review: str) -> tuple[str, list[str]]:
    blocks = SECTION_PATTERN.findall(review)
    if not blocks:
        return draft, []

    merged = draft
    touched: list[str] = []
    for section_name, addition in blocks:
        section = section_name.strip()
        content = addition.strip()
        if not section or not content:
            continue

        header_match = re.search(
            rf"(?im)^#{1,6}\s+.*{re.escape(section)}.*$",
            merged,
        )
        if not header_match:
            continue

        insert_at = len(merged)
        next_header = re.search(r"(?m)^#{1,6}\s+", merged[header_match.end() :])
        if next_header:
            insert_at = header_match.end() + next_header.start()

        merged = f"{merged[:insert_at].rstrip()}\n\n{content}\n\n{merged[insert_at:].lstrip()}"
        touched.append(section)

    return merged, touched


def _build_notes(review: str, touched_sections: list[str]) -> str:
    section_lines = "\n".join(f"- {name}" for name in touched_sections) if touched_sections else "- None"
    return (
        "# Review Notes\n\n"
        "## Sections Updated\n"
        f"{section_lines}\n\n"
        "## Peer Review Snapshot\n"
        f"{review.strip()}\n"
    )


def _extract_references(merged_draft: str) -> str:
    match = re.search(
        r"(?is)^#{1,6}\s*(references|bibliography)\s*$([\s\S]*)",
        merged_draft,
        flags=re.MULTILINE,
    )
    if match:
        return f"# References\n\n{match.group(2).strip()}\n"
    return "# References\n\nNo references section found.\n"


class S13Archive(Stage):
    @property
    def name(self) -> str:
        return "S13"

    @property
    def description(self) -> str:
        return "Archive and vault sync"

    def run(self, ctx: StageContext) -> StageResult:
        draft = safe_read(ctx.paper_dir / "draft.md")
        review = safe_read(ctx.state_dir / "s11_revised.md")

        merged_draft, touched_sections = _merge_section_additions(draft, review)
        notes = _build_notes(review, touched_sections)
        references = _extract_references(merged_draft)

        draft_path = ctx.paper_dir / "draft.md"
        notes_path = ctx.paper_dir / "notes.md"
        refs_path = ctx.paper_dir / "references.md"
        atomic_write(draft_path, merged_draft)
        atomic_write(notes_path, notes)
        atomic_write(refs_path, references)

        try:
            vault = VaultSync(ctx.config.vault, ctx.logger)
            vault.sync_files(
                [(draft_path, "draft.md"), (notes_path, "notes.md"), (refs_path, "references.md")],
                ctx.slug,
            )
        except Exception as exc:
            ctx.logger.warn(f"S13 vault sync skipped: {exc}")

        return StageResult(content=merged_draft)
