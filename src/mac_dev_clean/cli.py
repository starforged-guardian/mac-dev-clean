from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Sequence, Set

from .age import parse_age
from .cleaner import clean_targets
from .output import clean_report_json, render_clean_table, render_scan_table, scan_report_json
from .scanner import scan


FLAG_TO_CATEGORIES = {
    "xcode_derived_data": {"xcode-derived-data", "xcode-module-cache"},
    "simulator_caches": {"simulator-caches"},
    "brew_cache": {"brew-cache"},
    "npm_cache": {"npm-cache"},
    "gradle_cache": {"gradle-cache"},
    "node_modules": {"node-modules"},
}


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        if args.command in {"scan", "report"}:
            return run_scan(args)
        if args.command == "clean":
            return run_clean(args, parser)
        if args.command in {None, "interactive"}:
            return run_interactive(args, parser)
    except ValueError as exc:
        parser.error(str(exc))
    return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mac-dev-clean",
        description="Safely scan and clean common macOS developer caches.",
    )
    parser.set_defaults(
        command="interactive",
        search_root=[],
        include_node_modules=False,
        older_than=None,
    )
    subparsers = parser.add_subparsers(dest="command")

    scan_parser = subparsers.add_parser(
        "scan",
        help="Scan common developer cache locations without deleting anything.",
    )
    add_scan_options(scan_parser)

    clean_parser = subparsers.add_parser(
        "clean",
        help="Clean selected cache categories. Requires explicit category flags.",
    )
    add_scan_root_options(clean_parser)
    clean_parser.add_argument(
        "--xcode-derived-data",
        action="store_true",
        help="Clean Xcode DerivedData and module cache.",
    )
    clean_parser.add_argument(
        "--simulator-caches",
        action="store_true",
        help="Clean CoreSimulator caches and logs.",
    )
    clean_parser.add_argument(
        "--brew-cache",
        action="store_true",
        help="Clean Homebrew's cache directory.",
    )
    clean_parser.add_argument("--npm-cache", action="store_true", help="Clean npm cache and logs.")
    clean_parser.add_argument(
        "--gradle-cache",
        action="store_true",
        help="Clean Gradle caches, daemons, and wrapper distributions.",
    )
    clean_parser.add_argument(
        "--node-modules",
        action="store_true",
        help="Clean discovered node_modules directories.",
    )
    clean_parser.add_argument(
        "--older-than",
        help="Only include node_modules older than this age, such as 60d or 2w.",
    )
    clean_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be removed without deleting files.",
    )
    clean_parser.add_argument("--json", action="store_true", help="Print JSON output.")

    interactive_parser = subparsers.add_parser(
        "interactive",
        help="Scan cleanable cache locations and prompt before deleting them.",
    )
    add_scan_root_options(interactive_parser)
    interactive_parser.add_argument(
        "--include-node-modules",
        action="store_true",
        help="Also include discovered node_modules directories. Requires --older-than.",
    )
    interactive_parser.add_argument(
        "--older-than",
        help="Only include node_modules older than this age, such as 60d or 2w.",
    )

    report_parser = subparsers.add_parser(
        "report",
        help="Produce a disk usage report. This never deletes files.",
    )
    add_scan_options(report_parser)

    return parser


def add_scan_options(parser: argparse.ArgumentParser) -> None:
    add_scan_root_options(parser)
    parser.add_argument("--json", action="store_true", help="Print JSON output.")
    parser.add_argument("--older-than", help="Only include node_modules older than this age, such as 60d or 2w.")
    parser.add_argument("--no-node-modules", action="store_true", help="Skip recursive node_modules discovery.")


def add_scan_root_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--search-root",
        action="append",
        type=Path,
        default=[],
        help="Directory to search for node_modules. Can be passed more than once.",
    )


def run_scan(args: argparse.Namespace) -> int:
    older_than = parse_age(args.older_than) if args.older_than else None
    items = scan(
        search_roots=args.search_root or None,
        include_node_modules=not args.no_node_modules,
        node_modules_older_than=older_than,
        now=datetime.now(timezone.utc),
    )
    print(scan_report_json(items) if args.json else render_scan_table(items))
    return 0


def run_clean(args: argparse.Namespace, parser: argparse.ArgumentParser) -> int:
    selected = selected_categories(args)
    if not selected:
        parser.error("clean requires at least one explicit category flag")
    if args.node_modules and not args.older_than:
        parser.error("--node-modules requires --older-than, for example --older-than 60d")

    older_than = parse_age(args.older_than) if args.older_than else None
    include_node_modules = "node-modules" in selected
    items = scan(
        search_roots=args.search_root or None,
        include_node_modules=include_node_modules,
        node_modules_older_than=older_than,
        now=datetime.now(timezone.utc),
    )
    targets = [item for item in items if item.category in selected and item.cleanable]
    results = clean_targets(targets, dry_run=args.dry_run)
    print(clean_report_json(results) if args.json else render_clean_table(results))
    return 1 if any(result.error for result in results) else 0


def run_interactive(args: argparse.Namespace, parser: argparse.ArgumentParser) -> int:
    if args.include_node_modules and not args.older_than:
        parser.error(
            "interactive --include-node-modules requires --older-than, for example --older-than 60d"
        )

    older_than = parse_age(args.older_than) if args.older_than else None
    items = scan(
        search_roots=args.search_root or None,
        include_node_modules=args.include_node_modules,
        node_modules_older_than=older_than,
        now=datetime.now(timezone.utc),
    )
    targets = [item for item in items if item.cleanable]
    if not targets:
        print("No cleanable developer cache locations found.")
        return 0

    print(render_scan_table(targets))
    print()
    if not prompt_yes_no("Delete these cleanable items? [y/N] "):
        print("Canceled. Nothing deleted.")
        return 0

    results = clean_targets(targets)
    print(render_clean_table(results))
    return 1 if any(result.error for result in results) else 0


def prompt_yes_no(message: str) -> bool:
    while True:
        try:
            response = input(message)
        except EOFError:
            return False
        normalized = response.strip().lower()
        if normalized in {"y", "yes"}:
            return True
        if normalized in {"", "n", "no"}:
            return False
        print("Please answer y or n.")


def selected_categories(args: argparse.Namespace) -> Set[str]:
    selected: Set[str] = set()
    for arg_name, categories in FLAG_TO_CATEGORIES.items():
        if getattr(args, arg_name):
            selected.update(categories)
    return selected


if __name__ == "__main__":
    raise SystemExit(main())
