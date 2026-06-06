from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Iterable, List

from .model import CleanResult, ScanTarget, human_bytes


def scan_report_json(items: Iterable[ScanTarget]) -> str:
    targets = list(items)
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total_bytes": sum(item.size_bytes for item in targets),
        "total": human_bytes(sum(item.size_bytes for item in targets)),
        "count": len(targets),
        "items": [item.to_dict() for item in targets],
    }
    return json.dumps(payload, indent=2, sort_keys=True)


def clean_report_json(results: Iterable[CleanResult]) -> str:
    items = list(results)
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "dry_run": any(item.dry_run for item in items),
        "total_bytes": sum(item.size_bytes for item in items if not item.error),
        "total": human_bytes(sum(item.size_bytes for item in items if not item.error)),
        "count": len(items),
        "items": [item.to_dict() for item in items],
    }
    return json.dumps(payload, indent=2, sort_keys=True)


def render_scan_table(items: Iterable[ScanTarget]) -> str:
    targets = list(items)
    if not targets:
        return "No supported developer cache locations found."

    rows = [
        [
            item.category,
            human_bytes(item.size_bytes),
            _format_modified(item),
            "yes" if item.cleanable else "no",
            str(item.path),
        ]
        for item in targets
    ]
    body = _render_table(["Category", "Size", "Modified", "Cleanable", "Path"], rows)
    total = human_bytes(sum(item.size_bytes for item in targets))
    return f"{body}\n\nTotal: {total} across {len(targets)} item(s)"


def render_clean_table(results: Iterable[CleanResult]) -> str:
    items = list(results)
    if not items:
        return "No matching cleanable targets found."

    rows: List[List[str]] = []
    for item in items:
        if item.error:
            status = "error"
        elif item.dry_run:
            status = "would remove"
        elif item.removed:
            status = "removed"
        else:
            status = "skipped"
        rows.append(
            [
                status,
                item.category,
                human_bytes(item.size_bytes),
                str(item.path),
            ]
        )

    body = _render_table(["Status", "Category", "Size", "Path"], rows)
    total = human_bytes(sum(item.size_bytes for item in items if not item.error))
    return f"{body}\n\nTotal selected: {total} across {len(items)} item(s)"


def _render_table(headers: List[str], rows: List[List[str]]) -> str:
    widths = [len(header) for header in headers]
    for row in rows:
        for index, cell in enumerate(row):
            widths[index] = max(widths[index], len(cell))

    lines = [
        "  ".join(header.ljust(widths[index]) for index, header in enumerate(headers)),
        "  ".join("-" * width for width in widths),
    ]
    for row in rows:
        lines.append("  ".join(cell.ljust(widths[index]) for index, cell in enumerate(row)))
    return "\n".join(lines)


def _format_modified(item: ScanTarget) -> str:
    if item.modified_at is None:
        return "unknown"
    return item.modified_at.astimezone(timezone.utc).strftime("%Y-%m-%d")

