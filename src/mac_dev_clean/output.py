from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Iterable, List, Set, Tuple

from .model import CleanResult, ScanTarget, human_bytes


SCAN_RECOMMENDATIONS: Tuple[Tuple[str, Set[str], str], ...] = (
    (
        "Xcode DeviceSupport",
        {"xcode-device-support"},
        "mac-dev-clean clean --xcode-device-support --dry-run",
    ),
    (
        "Xcode build artifacts",
        {"xcode-derived-data", "xcode-module-cache"},
        "mac-dev-clean clean --xcode-derived-data --dry-run",
    ),
    (
        "Xcode documentation cache",
        {"xcode-documentation-cache"},
        "mac-dev-clean clean --xcode-documentation-cache --dry-run",
    ),
    (
        "simulator caches",
        {"simulator-caches"},
        "mac-dev-clean clean --simulator-caches --dry-run",
    ),
    (
        "Homebrew cache",
        {"brew-cache"},
        "mac-dev-clean clean --brew-cache --dry-run",
    ),
    (
        "package and tool caches",
        {
            "npm-cache",
            "pnpm-cache",
            "node-tool-cache",
            "python-cache",
            "swiftpm-cache",
            "go-cache",
            "rust-cache",
            "gradle-cache",
        },
        "mac-dev-clean clean --package-caches --dry-run",
    ),
    (
        "browser caches",
        {"browser-cache"},
        "mac-dev-clean clean --browser-caches --dry-run",
    ),
    (
        "old node_modules",
        {"node-modules"},
        "mac-dev-clean clean --node-modules --older-than 60d --dry-run",
    ),
)


def scan_report_json(items: Iterable[ScanTarget]) -> str:
    targets = list(items)
    cleanable_total = sum(item.size_bytes for item in targets if item.cleanable)
    report_only_total = sum(item.size_bytes for item in targets if not item.cleanable)
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total_bytes": sum(item.size_bytes for item in targets),
        "total": human_bytes(sum(item.size_bytes for item in targets)),
        "cleanable_total_bytes": cleanable_total,
        "cleanable_total": human_bytes(cleanable_total),
        "report_only_total_bytes": report_only_total,
        "report_only_total": human_bytes(report_only_total),
        "count": len(targets),
        "recommendations": [
            {
                "label": label,
                "size_bytes": size,
                "size": human_bytes(size),
                "command": command,
            }
            for size, label, command in _quick_wins(targets)
        ],
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
    summary = _render_scan_summary(targets, total)
    quick_wins = _render_quick_wins(targets)
    sections = [body, summary]
    if quick_wins:
        sections.append(quick_wins)
    return "\n\n".join(sections)


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


def _render_scan_summary(targets: List[ScanTarget], total: str) -> str:
    cleanable_total = sum(item.size_bytes for item in targets if item.cleanable)
    report_only_total = sum(item.size_bytes for item in targets if not item.cleanable)
    lines = [f"Total: {total} across {len(targets)} item(s)"]
    lines.append(
        "Potential cleanup: "
        f"{human_bytes(cleanable_total)} cleanable"
        f" | {human_bytes(report_only_total)} report-only"
    )
    return "\n".join(lines)


def _render_quick_wins(targets: List[ScanTarget]) -> str:
    wins = _quick_wins(targets)
    if not wins:
        return ""

    lines = ["Quick wins:"]
    for size, label, command in wins:
        lines.append(f"- {human_bytes(size)} {label}: {command}")
    lines.append("Review the dry run, then rerun without --dry-run to delete.")
    return "\n".join(lines)


def _quick_wins(targets: List[ScanTarget]) -> List[Tuple[int, str, str]]:
    wins: List[Tuple[int, str, str]] = []
    for label, categories, command in SCAN_RECOMMENDATIONS:
        size = sum(
            item.size_bytes
            for item in targets
            if item.cleanable and item.category in categories
        )
        if size:
            wins.append((size, label, command))

    return sorted(wins, reverse=True)[:3]


def _format_modified(item: ScanTarget) -> str:
    if item.modified_at is None:
        return "unknown"
    return item.modified_at.astimezone(timezone.utc).strftime("%Y-%m-%d")
