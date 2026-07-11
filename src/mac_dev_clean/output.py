from __future__ import annotations

import json
import textwrap
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, List, Set, Tuple

from .model import CleanResult, ScanTarget, human_bytes


SCAN_RECOMMENDATIONS: Tuple[Tuple[str, Set[str], str], ...] = (
    (
        "simulator runtime caches",
        {"simulator-dyld-cache"},
        "mac-dev-clean clean --simulator-dyld-cache --dry-run",
    ),
    (
        "XCTest simulator clones",
        {"xcode-test-devices"},
        "mac-dev-clean clean --xcode-test-devices --dry-run",
    ),
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
        "project-local Xcode build artifacts",
        {"project-derived-data"},
        "mac-dev-clean clean --project-derived-data --dry-run",
    ),
    (
        "Xcode documentation cache",
        {"xcode-documentation-cache"},
        "mac-dev-clean clean --xcode-documentation-cache --dry-run",
    ),
    (
        "Xcode device logs",
        {"xcode-device-logs"},
        "mac-dev-clean clean --xcode-device-logs --dry-run",
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
        "editor and updater caches",
        {"editor-cache", "updater-cache"},
        "mac-dev-clean clean --editor-caches --dry-run",
    ),
    (
        "downloaded wallpaper videos",
        {"wallpaper-cache"},
        "mac-dev-clean clean --wallpaper-cache --dry-run",
    ),
    (
        "old node_modules",
        {"node-modules"},
        "mac-dev-clean clean --node-modules --older-than 60d --dry-run",
    ),
)


def scan_report_json(items: Iterable[ScanTarget]) -> str:
    targets = list(items)
    cleanable_total = sum(_counted_size(item) for item in targets if item.cleanable)
    report_only_total = sum(_counted_size(item) for item in targets if not item.cleanable)
    total_bytes = sum(_counted_size(item) for item in targets)
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total_bytes": total_bytes,
        "total": human_bytes(total_bytes),
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
    total_bytes = sum(_counted_size(item) for item in items if not item.error)
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "dry_run": any(item.dry_run for item in items),
        "total_bytes": total_bytes,
        "total": human_bytes(total_bytes),
        "count": len(items),
        "items": [item.to_dict() for item in items],
    }
    return json.dumps(payload, indent=2, sort_keys=True)


def render_scan_table(items: Iterable[ScanTarget]) -> str:
    targets = list(items)
    if not targets:
        return "No supported developer cache locations found."

    cleanable = [item for item in targets if item.cleanable]
    review_only = [item for item in targets if not item.cleanable]
    summary = _render_scan_summary(targets)
    quick_wins = _render_quick_wins(targets)
    sections = [summary]
    if quick_wins:
        sections.append(quick_wins)
    if cleanable:
        sections.append(_render_scan_items("Cleanable items", cleanable))
    if review_only:
        sections.append(_render_review_items(review_only))
    return "\n\n".join(sections)


def render_clean_table(results: Iterable[CleanResult]) -> str:
    items = list(results)
    if not items:
        return "No matching cleanable targets found."

    entries: List[str] = []
    for item in items:
        if item.error:
            status = "error"
        elif item.dry_run:
            status = "would remove"
        elif item.removed and item.category == "xcode-test-devices":
            status = "delete requested"
        elif item.removed:
            status = "removed"
        else:
            status = "skipped"
        entries.append(
            _render_entry(
                f"{status}  |  {item.category}  |  "
                f"{_display_size(item.category, item.size_bytes)}",
                item.path,
            )
        )

    body = _section("Cleanup results", "\n\n".join(entries))
    total = human_bytes(sum(_counted_size(item) for item in items if not item.error))
    output = f"{body}\n\nTotal selected: {total} across {len(items)} item(s)"
    if any(item.category == "xcode-test-devices" and item.removed for item in items):
        output += (
            "\n\nCoreSimulator accepted the XCTest clone deletion request. "
            "APFS may reclaim shared blocks in the background, so df and Finder "
            "free-space values can take several minutes to increase."
        )
    return output


def _render_scan_summary(targets: List[ScanTarget]) -> str:
    cleanable_total = sum(_counted_size(item) for item in targets if item.cleanable)
    report_only_total = sum(_counted_size(item) for item in targets if not item.cleanable)
    cleanable_count = sum(1 for item in targets if item.cleanable)
    report_only_count = len(targets) - cleanable_count
    total = cleanable_total + report_only_total
    body = "\n".join(
        [
            f"  Cleanable:    {human_bytes(cleanable_total)} across {cleanable_count} item(s)",
            f"  Review only:  {human_bytes(report_only_total)} across {report_only_count} item(s)",
            f"  Total found:  {human_bytes(total)} across {len(targets)} item(s)",
        ]
    )
    return _section("Cleanup summary", body)


def _render_quick_wins(targets: List[ScanTarget]) -> str:
    wins = _quick_wins(targets)
    if not wins:
        return ""

    entries: List[str] = []
    for size, label, command in wins:
        entries.append(f"  {human_bytes(size)}  {label}\n    Preview: {command}")
    body = "\n\n".join(entries)
    body += "\n\n  Review a preview, then rerun without --dry-run to delete."
    return _section("Quick wins", body)


def _render_scan_items(title: str, items: List[ScanTarget]) -> str:
    entries = []
    for item in items:
        entries.append(
            _render_entry(
                f"{item.category}  |  {_display_size(item.category, item.size_bytes)}  "
                f"|  modified {_format_modified(item)}",
                item.path,
            )
        )
    return _section(f"{title} ({len(items)})", "\n\n".join(entries))


def _render_review_items(items: List[ScanTarget]) -> str:
    entries = []
    for item in items:
        lines = [
            f"  {item.label}  |  {_display_size(item.category, item.size_bytes)}",
            f"    Path: {_display_path(item.path)}",
        ]
        if item.note:
            lines.append(
                textwrap.fill(
                    f"Note: {item.note}",
                    width=96,
                    initial_indent="    ",
                    subsequent_indent="          ",
                )
            )
        entries.append("\n".join(lines))
    return _section(f"Review-only items ({len(items)})", "\n\n".join(entries))


def _render_entry(heading: str, path: Path) -> str:
    return f"  {heading}\n    Path: {_display_path(path)}"


def _section(title: str, body: str) -> str:
    return f"{title}\n{'-' * len(title)}\n{body}"


def _display_path(path: Path) -> str:
    value = str(path)
    home = str(Path.home())
    if value == home:
        return "~"
    if value.startswith(home + "/"):
        return "~" + value[len(home) :]
    return value


def _quick_wins(targets: List[ScanTarget]) -> List[Tuple[int, str, str]]:
    wins: List[Tuple[int, str, str]] = []
    for label, categories, command in SCAN_RECOMMENDATIONS:
        size = sum(
            _counted_size(item)
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


def _display_size(category: str, size_bytes: int) -> str:
    if category == "xcode-test-devices":
        return "shared/unknown"
    return human_bytes(size_bytes)


def _counted_size(item: object) -> int:
    if getattr(item, "category", "") == "xcode-test-devices":
        return 0
    return int(getattr(item, "size_bytes", 0))
