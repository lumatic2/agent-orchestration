from __future__ import annotations

import re
import shutil
import subprocess
from datetime import datetime
from pathlib import Path
from pipeline.core.platform import get_orch_path, get_repo_dir

from pipeline.core.file_ops import atomic_write, safe_read
from pipeline.core.platform import is_windows, to_native_path
from pipeline.models.stage_result import StageResult
from pipeline.stages.base import Stage, StageContext
from pipeline.vault.ssh_sync import VaultSync


from pipeline.core.platform import get_orch_path, get_repo_dir
ORCH_PATH = get_orch_path()


def _extract_title(md: str) -> str:
    # Match # Title (not ## or ###)
    match = re.search(r"^#\s+(?!#)(.+?)\s*$", md, flags=re.MULTILINE)
    if match:
        return match.group(1).strip()
    # Fallback: first heading of any level
    match = re.search(r"^#{1,3}\s+(.+?)\s*$", md, flags=re.MULTILINE)
    if match:
        heading = match.group(1).strip()
        # Skip if it's just "초록" or "Abstract"
        if heading.lower() not in ("초록", "abstract"):
            return heading
    return "Research Paper"


def _extract_abstract(md: str) -> str:
    # Match ## or ### Abstract/초록
    match = re.search(r"^#{2,3}\s*(Abstract|초록)\s*$", md, flags=re.IGNORECASE | re.MULTILINE)
    if not match:
        return ""
    tail = md[match.end():]
    # Stop at next heading of same or higher level
    next_heading = re.search(r"^#{1,3}\s+", tail, flags=re.MULTILINE)
    block = tail[:next_heading.start()] if next_heading else tail
    return block.strip()


def _extract_body(md: str) -> str:
    lines = md.splitlines()
    body: list[str] = []
    skip_title = True
    in_abstract = False
    abstract_seen = False
    for raw in lines:
        line = raw.rstrip("\n")
        stripped = line.strip()
        # Skip first heading (title)
        if skip_title and re.match(r"^#{1,3}\s+", stripped):
            if not re.match(r"^#{1,3}\s*(Abstract|초록)\s*$", stripped, re.IGNORECASE):
                skip_title = False
                continue
        # Detect abstract section
        if re.match(r"^#{1,3}\s*(Abstract|초록)\s*$", stripped, re.IGNORECASE):
            in_abstract = True
            abstract_seen = True
            continue
        if in_abstract and re.match(r"^#{1,3}\s+", stripped):
            in_abstract = False
        if in_abstract:
            continue
        if not skip_title:
            body.append(line)
    if not abstract_seen:
        return "\n".join(lines[1:]).strip()
    return "\n".join(body).strip()


def _markdown_to_typst(markdown_body: str) -> str:
    out: list[str] = []
    for line in markdown_body.splitlines():
        if line.startswith("### "):
            out.append(f"=== {line[4:].strip()}")
        elif line.startswith("## "):
            out.append(f"== {line[3:].strip()}")
        elif line.startswith("# "):
            out.append(f"= {line[2:].strip()}")
        else:
            out.append(line)
    return "\n".join(out).strip()


def _escape_typst(s: str) -> str:
    return (
        s.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("#", "\\#")
        .replace("[", "\\[")
        .replace("]", "\\]")
    )


def _compute_display_slug(ctx: StageContext) -> str:
    if len(ctx.slug) >= 4:
        return ctx.slug
    s01 = safe_read(ctx.state_dir / "s01_scope.md")
    tokens = re.findall(r"[A-Za-z][A-Za-z0-9-]{2,}", s01)
    if tokens:
        return "-".join(tokens[:3]).lower()
    return f"research-{datetime.now():%Y%m%d}"


class S16Pdf(Stage):
    @property
    def name(self) -> str:
        return "S16"

    @property
    def description(self) -> str:
        return "PDF generation"

    def run(self, ctx: StageContext) -> StageResult:
        draft = safe_read(ctx.paper_dir / "draft.md")
        template_key = (ctx.config.templates.default or "A").strip().upper()
        if template_key not in {"A", "B", "C", "D"}:
            template_key = "A"

        template_path = get_repo_dir() / ctx.config.templates.typst_dir / f"paper_{template_key}.typ"
        if not template_path.exists():
            ctx.logger.warn(f"Template not found: {template_path}. Falling back to paper_A.typ")
            template_path = get_repo_dir() / ctx.config.templates.typst_dir / "paper_A.typ"

        body_md = _extract_body(draft)
        # Force line break before inline headings (LLM sometimes writes ### mid-paragraph)
        body_md = re.sub(r"(?<!\n)(#{2,4}\s+)", r"\n\n\1", body_md)
        # Promote heading levels: ### → ##, #### → ### (so pandoc maps to proper typst levels)
        body_md = re.sub(r"^####\s+", "### ", body_md, flags=re.MULTILINE)
        body_md = re.sub(r"^###\s+", "## ", body_md, flags=re.MULTILINE)
        body_md_path = ctx.paper_dir / "draft_body.md"
        body_typ_path = ctx.paper_dir / "draft_body.typ"
        atomic_write(body_md_path, body_md)

        paper_cwd = to_native_path(str(ctx.paper_dir)) if is_windows() else str(ctx.paper_dir)
        pandoc_ok = False
        try:
            subprocess.run(
                ["pandoc", "draft_body.md", "-t", "typst", "-o", "draft_body.typ"],
                cwd=paper_cwd,
                timeout=60,
                check=True,
                capture_output=True,
                encoding="utf-8",
                errors="replace",
            )
            pandoc_ok = True
        except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as exc:
            ctx.logger.warn(f"Pandoc conversion failed, using direct fallback body: {exc}")

        if pandoc_ok:
            body_typ = safe_read(body_typ_path).strip()
        else:
            body_typ = _markdown_to_typst(body_md)

        template_text = safe_read(template_path)
        title = _escape_typst(_extract_title(draft))
        abstract = _escape_typst(_extract_abstract(draft))

        final_typ = (
            f"{template_text.rstrip()}\n\n"
            "#show: conf.with(\n"
            f'  title: "{title}",\n'
            f"  abstract: [{abstract}],\n"
            ")\n\n"
            f"{body_typ.strip()}\n"
        )
        typ_path = ctx.paper_dir / f"{ctx.slug}.typ"
        atomic_write(typ_path, final_typ)

        pdf_path = ctx.paper_dir / f"{ctx.slug}.pdf"
        try:
            subprocess.run(
                ["typst", "compile", f"{ctx.slug}.typ", f"{ctx.slug}.pdf"],
                cwd=paper_cwd,
                timeout=120,
                check=True,
                capture_output=True,
                encoding="utf-8",
                errors="replace",
            )
        except subprocess.CalledProcessError as exc:
            err_detail = (exc.stderr or exc.stdout or str(exc))[:500]
            ctx.logger.warn(f"Typst compile failed: {err_detail}")
            return StageResult(content=f"PDF generation skipped: {err_detail}")
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError) as exc:
            ctx.logger.warn(f"Typst compile failed: {exc}")
            return StageResult(content=f"PDF generation skipped: {exc}")

        desktop_dir = Path.home() / "Desktop" / "research"
        display_slug = _compute_display_slug(ctx)
        desktop_dir.mkdir(parents=True, exist_ok=True)
        desktop_pdf = desktop_dir / f"{display_slug}.pdf"
        try:
            shutil.copy2(pdf_path, desktop_pdf)
        except OSError as exc:
            ctx.logger.warn(f"Desktop copy failed: {exc}")

        try:
            VaultSync(ctx.config.vault, ctx.logger).sync_file(pdf_path, f"{display_slug}.pdf", ctx.slug)
        except Exception as exc:
            ctx.logger.warn(f"Vault sync failed: {exc}")

        return StageResult(content=f"PDF generated: {pdf_path}")
