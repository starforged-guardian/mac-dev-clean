from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from typing import Iterable, List, Optional, Sequence

from .age import parse_age
from .model import human_bytes
from .sim_prune import (
    ActionReport,
    Device,
    Inventory,
    RuntimeImage,
    SimctlError,
    age_to_days,
    delete_devices,
    delete_runtimes,
    delete_unavailable,
    erase_unused,
    load_inventory,
    select_default_delete_devices,
)


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        if args.command in {None, "interactive"}:
            return run_interactive()

        if args.command == "list":
            inventory = load_inventory()
            print(
                json.dumps(inventory.to_dict(), indent=2, sort_keys=True)
                if args.json
                else render_inventory(inventory)
            )
            return 0

        if args.command == "delete-unavailable":
            inventory = load_inventory()
            report = delete_unavailable(inventory, dry_run=args.dry_run)
            print(render_action_json(report) if args.json else render_action_report(report))
            return 0

        if args.command == "delete-devices":
            if not args.name and not args.udid and not args.all_shutdown:
                parser.error("delete-devices requires --name, --udid, or --all-shutdown")
            inventory = load_inventory()
            report = delete_devices(
                inventory,
                names=args.name,
                udids=args.udid,
                all_shutdown=args.all_shutdown,
                keep_names=args.keep_name,
                keep_udids=args.keep_udid,
                dry_run=args.dry_run,
            )
            print(render_action_json(report) if args.json else render_action_report(report))
            return 0

        if args.command == "delete-runtimes":
            older_than_days = age_to_days(parse_age(args.older_than))
            inventory = load_inventory()
            report = delete_runtimes(
                inventory,
                older_than_days=older_than_days,
                dry_run=args.dry_run,
                keep_asset=args.keep_asset,
                now=datetime.now(timezone.utc),
            )
            print(render_action_json(report) if args.json else render_action_report(report))
            return 0

        if args.command == "erase-unused":
            older_than = parse_age(args.older_than) if args.older_than else None
            inventory = load_inventory()
            report = erase_unused(
                inventory,
                older_than=older_than,
                dry_run=args.dry_run,
                now=datetime.now(timezone.utc),
            )
            print(render_action_json(report) if args.json else render_action_report(report))
            return 0
    except ValueError as exc:
        parser.error(str(exc))
    except SimctlError as exc:
        print(f"xcode-sim-prune: simctl failed: {exc}", file=sys.stderr)
        return 1

    return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="xcode-sim-prune",
        description="Safely list and prune Xcode simulator devices and runtimes.",
    )
    parser.set_defaults(command="interactive")
    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser(
        "interactive",
        help="Scan safe simulator cleanup candidates and prompt before deleting them.",
    )

    list_parser = subparsers.add_parser("list", help="List simulator devices and runtime disk images.")
    list_parser.add_argument("--json", action="store_true", help="Print JSON output.")

    unavailable_parser = subparsers.add_parser(
        "delete-unavailable",
        help="Delete simulator devices unsupported by the current Xcode SDK.",
    )
    add_action_options(unavailable_parser)

    delete_devices_parser = subparsers.add_parser(
        "delete-devices",
        help="Delete selected shutdown simulator devices by exact name or UDID.",
    )
    delete_devices_parser.add_argument(
        "--name",
        action="append",
        default=[],
        help="Exact simulator device name to delete. Can be passed more than once.",
    )
    delete_devices_parser.add_argument(
        "--udid",
        action="append",
        default=[],
        help="Simulator UDID to delete. Can be passed more than once.",
    )
    delete_devices_parser.add_argument(
        "--all-shutdown",
        action="store_true",
        help="Select every shutdown simulator device.",
    )
    delete_devices_parser.add_argument(
        "--keep-name",
        action="append",
        default=[],
        help="Exact simulator device name to keep when using broad selections.",
    )
    delete_devices_parser.add_argument(
        "--keep-udid",
        action="append",
        default=[],
        help="Simulator UDID to keep when using broad selections.",
    )
    add_action_options(delete_devices_parser)

    runtime_parser = subparsers.add_parser(
        "delete-runtimes",
        help="Delete simulator runtime images not used within the requested age.",
    )
    runtime_parser.add_argument(
        "--older-than",
        required=True,
        help="Age threshold, such as 180d or 26w.",
    )
    runtime_parser.add_argument(
        "--keep-asset",
        action="store_true",
        help="Ask simctl to keep the associated mobile asset.",
    )
    add_action_options(runtime_parser)

    erase_parser = subparsers.add_parser(
        "erase-unused",
        help="Erase shutdown simulator devices that appear unused.",
    )
    erase_parser.add_argument(
        "--older-than",
        help="Also include shutdown devices last booted before this age, such as 60d.",
    )
    add_action_options(erase_parser)

    return parser


def run_interactive() -> int:
    inventory = load_inventory()
    candidates = select_default_delete_devices(inventory.devices)
    if not candidates:
        print("No safe simulator cleanup candidates found.")
        return 0

    target_udids = [device.udid for device in candidates]
    preview = delete_devices(inventory, udids=target_udids, dry_run=True)

    print("Safe simulator cleanup candidates")
    print()
    print(render_action_report(preview))
    print()
    if not prompt_yes_no("Delete these shutdown simulator devices? [y/N] "):
        print("Canceled. Nothing deleted.")
        return 0

    result = delete_devices(inventory, udids=target_udids, dry_run=False)
    print(render_action_report(result))
    return 0


def add_action_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be affected without changing anything.",
    )
    parser.add_argument("--json", action="store_true", help="Print JSON output.")


def render_inventory(inventory: Inventory) -> str:
    sections = [
        render_devices(inventory.devices),
        render_runtimes(inventory.runtimes),
    ]
    device_total = human_bytes(sum(device.total_size_bytes for device in inventory.devices))
    runtime_total = human_bytes(sum(runtime.size_bytes for runtime in inventory.runtimes))
    sections.append(f"Device data: {device_total} across {len(inventory.devices)} device(s)")
    sections.append(f"Runtime images: {runtime_total} across {len(inventory.runtimes)} runtime image(s)")
    return "\n\n".join(section for section in sections if section)


def render_devices(devices: Iterable[Device]) -> str:
    items = list(devices)
    if not items:
        return "Devices: none"
    rows = [
        [
            device.name,
            device.state,
            "yes" if device.is_available else "no",
            human_bytes(device.total_size_bytes),
            _format_datetime(device.last_booted_at),
            device.udid,
        ]
        for device in items
    ]
    return "Devices\n" + render_table(["Name", "State", "Available", "Size", "Last Booted", "UDID"], rows)


def render_runtimes(runtimes: Iterable[RuntimeImage]) -> str:
    items = list(runtimes)
    if not items:
        return "Runtime images: none"
    rows = [
        [
            runtime.name,
            runtime.version,
            runtime.build,
            runtime.state or "-",
            "yes" if runtime.deletable else "no",
            human_bytes(runtime.size_bytes),
            _format_datetime(runtime.last_used_at),
            runtime.identifier,
        ]
        for runtime in items
    ]
    return "Runtime Images\n" + render_table(
        ["Name", "Version", "Build", "State", "Deletable", "Size", "Last Used", "Image ID"],
        rows,
    )


def render_action_report(report: ActionReport) -> str:
    if not report.targets:
        return f"No targets for {report.action}."

    status = "Would affect" if report.dry_run else "Affected"
    rows: List[List[str]] = []
    for target in report.targets:
        rows.append(
            [
                str(target.get("name", target.get("runtime_identifier", ""))),
                str(target.get("state", "-")),
                str(target.get("total_size") or target.get("size") or "0 B"),
                str(target.get("udid") or target.get("identifier") or ""),
            ]
        )

    output = [
        f"{status} {len(report.targets)} target(s) for {report.action}",
        render_table(["Name", "State", "Size", "ID"], rows),
        "Command: " + " ".join(report.command),
    ]
    if report.stdout:
        output.append("simctl output:\n" + report.stdout)
    return "\n\n".join(output)


def render_action_json(report: ActionReport) -> str:
    return json.dumps(report.to_dict(), indent=2, sort_keys=True)


def render_table(headers: List[str], rows: List[List[str]]) -> str:
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


def _format_datetime(value: object) -> str:
    if value is None:
        return "never"
    if hasattr(value, "strftime"):
        return value.strftime("%Y-%m-%d")
    return str(value)


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


if __name__ == "__main__":
    raise SystemExit(main())
