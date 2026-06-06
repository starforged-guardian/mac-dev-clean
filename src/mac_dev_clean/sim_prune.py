from __future__ import annotations

import json
import re
import subprocess
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Optional, Sequence

from .model import human_bytes


Runner = Callable[[Sequence[str]], str]
XCRUN = "/usr/bin/xcrun"
SIMCTL_UDID_RE = re.compile(r"^[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$")


@dataclass(frozen=True)
class Device:
    runtime_identifier: str
    name: str
    udid: str
    state: str
    is_available: bool
    last_booted_at: Optional[datetime]
    data_size_bytes: int
    log_size_bytes: int

    @property
    def total_size_bytes(self) -> int:
        return self.data_size_bytes + self.log_size_bytes

    def to_dict(self) -> Dict[str, object]:
        return {
            "runtime_identifier": self.runtime_identifier,
            "name": self.name,
            "udid": self.udid,
            "state": self.state,
            "is_available": self.is_available,
            "last_booted_at": _datetime_to_json(self.last_booted_at),
            "data_size_bytes": self.data_size_bytes,
            "log_size_bytes": self.log_size_bytes,
            "total_size_bytes": self.total_size_bytes,
            "total_size": human_bytes(self.total_size_bytes),
        }


@dataclass(frozen=True)
class RuntimeImage:
    identifier: str
    runtime_identifier: str
    name: str
    version: str
    build: str
    platform_identifier: str
    state: str
    deletable: bool
    last_used_at: Optional[datetime]
    size_bytes: int
    path: str

    def to_dict(self) -> Dict[str, object]:
        return {
            "identifier": self.identifier,
            "runtime_identifier": self.runtime_identifier,
            "name": self.name,
            "version": self.version,
            "build": self.build,
            "platform_identifier": self.platform_identifier,
            "state": self.state,
            "deletable": self.deletable,
            "last_used_at": _datetime_to_json(self.last_used_at),
            "size_bytes": self.size_bytes,
            "size": human_bytes(self.size_bytes),
            "path": self.path,
        }


@dataclass(frozen=True)
class Inventory:
    devices: List[Device]
    runtimes: List[RuntimeImage]

    def to_dict(self) -> Dict[str, object]:
        device_total = sum(device.total_size_bytes for device in self.devices)
        runtime_total = sum(runtime.size_bytes for runtime in self.runtimes)
        return {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "device_count": len(self.devices),
            "device_total_bytes": device_total,
            "device_total": human_bytes(device_total),
            "runtime_count": len(self.runtimes),
            "runtime_total_bytes": runtime_total,
            "runtime_total": human_bytes(runtime_total),
            "devices": [device.to_dict() for device in self.devices],
            "runtimes": [runtime.to_dict() for runtime in self.runtimes],
        }


@dataclass(frozen=True)
class ActionReport:
    action: str
    dry_run: bool
    command: List[str]
    targets: List[Dict[str, object]]
    stdout: str = ""

    def to_dict(self) -> Dict[str, object]:
        return {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "action": self.action,
            "dry_run": self.dry_run,
            "command": self.command,
            "target_count": len(self.targets),
            "targets": self.targets,
            "stdout": self.stdout,
        }


class SimctlError(RuntimeError):
    pass


def run_simctl(args: Sequence[str]) -> str:
    process = subprocess.run(
        [XCRUN, "simctl", *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if process.returncode != 0:
        detail = process.stderr.strip() or process.stdout.strip()
        raise SimctlError(detail or f"simctl exited with {process.returncode}")
    return process.stdout


def load_inventory(runner: Runner = run_simctl) -> Inventory:
    devices = parse_devices_json(runner(["list", "--json", "devices"]))
    runtimes = parse_runtime_images_json(runner(["runtime", "list", "-j"]))
    return Inventory(devices=devices, runtimes=runtimes)


def parse_devices_json(raw: str) -> List[Device]:
    payload = json.loads(raw or "{}")
    devices_by_runtime = payload.get("devices", {})
    devices: List[Device] = []

    for runtime_identifier, runtime_devices in devices_by_runtime.items():
        for item in runtime_devices:
            devices.append(
                Device(
                    runtime_identifier=runtime_identifier,
                    name=str(item.get("name", "")),
                    udid=str(item.get("udid", "")),
                    state=str(item.get("state", "")),
                    is_available=bool(item.get("isAvailable", False)),
                    last_booted_at=parse_simctl_datetime(item.get("lastBootedAt")),
                    data_size_bytes=int(item.get("dataPathSize", 0) or 0),
                    log_size_bytes=int(item.get("logPathSize", 0) or 0),
                )
            )

    return sorted(devices, key=lambda device: device.total_size_bytes, reverse=True)


def parse_runtime_images_json(raw: str) -> List[RuntimeImage]:
    payload = json.loads(raw or "{}")
    entries: Iterable[tuple[str, Dict[str, object]]]
    if isinstance(payload.get("runtimes"), list):
        entries = (
            (str(item.get("identifier", "")), item)
            for item in payload.get("runtimes", [])
            if isinstance(item, dict)
        )
    else:
        entries = (
            (str(identifier), item)
            for identifier, item in payload.items()
            if isinstance(item, dict)
        )

    runtimes: List[RuntimeImage] = []
    for identifier, item in entries:
        runtime_identifier = str(item.get("runtimeIdentifier") or item.get("identifier") or "")
        bundle_path = str(item.get("runtimeBundlePath") or item.get("bundlePath") or "")
        name = str(item.get("name") or _runtime_name_from_path(bundle_path) or runtime_identifier)
        runtimes.append(
            RuntimeImage(
                identifier=identifier,
                runtime_identifier=runtime_identifier,
                name=name,
                version=str(item.get("version", "")),
                build=str(item.get("build") or item.get("buildversion") or ""),
                platform_identifier=str(item.get("platformIdentifier") or item.get("platform") or ""),
                state=str(item.get("state", "")),
                deletable=bool(item.get("deletable", item.get("isAvailable", False))),
                last_used_at=parse_simctl_datetime(item.get("lastUsedAt") or _latest_last_usage(item)),
                size_bytes=int(item.get("sizeBytes", 0) or 0),
                path=str(item.get("path") or bundle_path),
            )
        )

    return sorted(runtimes, key=lambda runtime: runtime.size_bytes, reverse=True)


def delete_unavailable(
    inventory: Inventory,
    runner: Runner = run_simctl,
    dry_run: bool = False,
) -> ActionReport:
    targets = [device for device in inventory.devices if not device.is_available]
    command = [XCRUN, "simctl", "delete", "unavailable"]
    stdout = "" if dry_run or not targets else runner(["delete", "unavailable"])
    return ActionReport(
        action="delete-unavailable",
        dry_run=dry_run,
        command=command,
        targets=[device.to_dict() for device in targets],
        stdout=stdout.strip(),
    )


def delete_runtimes(
    inventory: Inventory,
    older_than_days: int,
    runner: Runner = run_simctl,
    dry_run: bool = False,
    keep_asset: bool = False,
    now: Optional[datetime] = None,
) -> ActionReport:
    targets = select_old_runtimes(inventory.runtimes, timedelta(days=older_than_days), now=now)
    args = ["runtime", "delete", "--notUsedSinceDays", str(older_than_days)]
    if dry_run:
        args.append("--dry-run")
    if keep_asset:
        args.append("--keep-asset")
    stdout = "" if not targets else runner(args)
    return ActionReport(
        action="delete-runtimes",
        dry_run=dry_run,
        command=[XCRUN, "simctl", *args],
        targets=[runtime.to_dict() for runtime in targets],
        stdout=stdout.strip(),
    )


def erase_unused(
    inventory: Inventory,
    runner: Runner = run_simctl,
    older_than: Optional[timedelta] = None,
    dry_run: bool = False,
    now: Optional[datetime] = None,
) -> ActionReport:
    targets = select_unused_devices(inventory.devices, older_than=older_than, now=now)
    args = ["erase", *[device.udid for device in targets]]
    command = [XCRUN, "simctl", *args]
    stdout = "" if dry_run or not targets else runner(args)
    return ActionReport(
        action="erase-unused",
        dry_run=dry_run,
        command=command,
        targets=[device.to_dict() for device in targets],
        stdout=stdout.strip(),
    )


def select_old_runtimes(
    runtimes: Iterable[RuntimeImage],
    older_than: timedelta,
    now: Optional[datetime] = None,
) -> List[RuntimeImage]:
    cutoff = (now or datetime.now(timezone.utc)) - older_than
    return [
        runtime
        for runtime in runtimes
        if runtime.deletable and (runtime.last_used_at is None or runtime.last_used_at <= cutoff)
    ]


def select_unused_devices(
    devices: Iterable[Device],
    older_than: Optional[timedelta] = None,
    now: Optional[datetime] = None,
) -> List[Device]:
    cutoff = (now or datetime.now(timezone.utc)) - older_than if older_than else None
    selected: List[Device] = []
    for device in devices:
        if not device.is_available or device.state.lower() == "booted":
            continue
        if not is_safe_simctl_udid(device.udid):
            continue
        if cutoff is None:
            if device.last_booted_at is None:
                selected.append(device)
        elif device.last_booted_at is None or device.last_booted_at <= cutoff:
            selected.append(device)
    return selected


def age_to_days(age: timedelta) -> int:
    seconds = age.total_seconds()
    days = int(seconds // 86400)
    if seconds % 86400:
        days += 1
    return max(days, 1)


def is_safe_simctl_udid(value: str) -> bool:
    return bool(SIMCTL_UDID_RE.match(value))


def parse_simctl_datetime(value: object) -> Optional[datetime]:
    if not value:
        return None
    text = str(value)
    if text.endswith("Z"):
        text = f"{text[:-1]}+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _latest_last_usage(item: Dict[str, object]) -> Optional[str]:
    usage = item.get("lastUsage")
    if not isinstance(usage, dict):
        return None
    values = [str(value) for value in usage.values() if value]
    return max(values) if values else None


def _runtime_name_from_path(path: str) -> str:
    if not path:
        return ""
    name = Path(path).name
    return name.removesuffix(".simruntime")


def _datetime_to_json(value: Optional[datetime]) -> Optional[str]:
    return value.isoformat() if value else None
