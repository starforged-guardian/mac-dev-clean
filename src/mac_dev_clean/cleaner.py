from __future__ import annotations

import os
import shutil
import stat
from pathlib import Path
from typing import Iterable, List

from .model import CleanResult, ScanTarget
from .sim_prune import SimctlError, delete_test_clones, load_device_set_inventory


DANGEROUS_NAMES = {"", ".", ".."}

CATEGORY_DELETE_MODES = {
    "xcode-derived-data": "contents",
    "xcode-module-cache": "contents",
    "xcode-documentation-cache": "contents",
    "xcode-device-support": "contents",
    "xcode-device-logs": "contents",
    "xcode-test-devices": "simctl-device-set",
    "simulator-caches": "contents",
    "brew-cache": "contents",
    "npm-cache": "contents",
    "pnpm-cache": "contents",
    "node-tool-cache": "contents",
    "python-cache": "contents",
    "swiftpm-cache": "contents",
    "go-cache": "contents",
    "rust-cache": "contents",
    "gradle-cache": "contents",
    "browser-cache": "contents",
    "node-modules": "tree",
}

FIXED_CATEGORY_SUFFIXES = {
    "xcode-derived-data": (("Library", "Developer", "Xcode", "DerivedData"),),
    "xcode-module-cache": (("Library", "Developer", "Xcode", "ModuleCache.noindex"),),
    "xcode-documentation-cache": (
        ("Library", "Developer", "Xcode", "DocumentationCache"),
        ("Library", "Developer", "Xcode", "DocumentationIndex"),
    ),
    "xcode-device-support": (
        ("Library", "Developer", "Xcode", "iOS DeviceSupport"),
        ("Library", "Developer", "Xcode", "tvOS DeviceSupport"),
        ("Library", "Developer", "Xcode", "watchOS DeviceSupport"),
        ("Library", "Developer", "Xcode", "visionOS DeviceSupport"),
    ),
    "xcode-device-logs": (("Library", "Developer", "Xcode", "DeviceLogs"),),
    "xcode-test-devices": (("Library", "Developer", "XCTestDevices"),),
    "simulator-caches": (
        ("Library", "Developer", "CoreSimulator", "Caches"),
        ("Library", "Logs", "CoreSimulator"),
    ),
    "brew-cache": (("Library", "Caches", "Homebrew"),),
    "npm-cache": ((".npm", "_cacache"), (".npm", "_logs")),
    "pnpm-cache": (
        ("Library", "pnpm", "store"),
        ("Library", "Caches", "pnpm"),
    ),
    "node-tool-cache": (
        ("Library", "Caches", "node-gyp"),
        ("Library", "Caches", "typescript"),
        ("Library", "Caches", "bun"),
    ),
    "python-cache": (
        ("Library", "Caches", "pip"),
        (".cache", "pip"),
        ("Library", "Caches", "pypoetry"),
        (".cache", "pypoetry"),
    ),
    "swiftpm-cache": (("Library", "Caches", "org.swift.swiftpm"),),
    "go-cache": (
        ("Library", "Caches", "go-build"),
        ("go", "pkg", "mod"),
    ),
    "rust-cache": (
        (".cargo", "registry"),
        (".cargo", "git"),
    ),
    "gradle-cache": (
        (".gradle", "caches"),
        (".gradle", "daemon"),
        (".gradle", "wrapper", "dists"),
    ),
    "browser-cache": (
        ("Library", "Caches", "Google"),
        ("Library", "Caches", "BraveSoftware"),
        ("Library", "Caches", "Firefox"),
        ("Library", "Caches", "com.apple.Safari"),
    ),
}


def clean_targets(targets: Iterable[ScanTarget], dry_run: bool = False) -> List[CleanResult]:
    return [clean_target(target, dry_run=dry_run) for target in targets]


def clean_target(target: ScanTarget, dry_run: bool = False) -> CleanResult:
    error = validate_target(target)
    if error:
        return _result(target, dry_run=dry_run, removed=False, error=error)

    if dry_run:
        return _result(target, dry_run=True, removed=False)

    try:
        if target.delete_mode == "contents":
            _remove_contents(target.path)
        elif target.delete_mode == "tree":
            _remove_path(target.path)
        elif target.delete_mode == "simctl-device-set":
            inventory = load_device_set_inventory(target.path)
            delete_test_clones(inventory, target.path)
        else:
            return _result(
                target,
                dry_run=False,
                removed=False,
                error=f"unsupported delete mode: {target.delete_mode}",
            )
    except (OSError, SimctlError, ValueError) as exc:
        return _result(target, dry_run=False, removed=False, error=str(exc))

    return _result(target, dry_run=False, removed=True)


def validate_target(target: ScanTarget) -> str:
    path = target.path
    if not target.cleanable:
        return "target is report-only"
    expected_mode = CATEGORY_DELETE_MODES.get(target.category)
    if expected_mode is None:
        return "target category is not cleanable"
    if target.delete_mode != expected_mode:
        return "target delete mode does not match its category"
    if not path.exists():
        return "path no longer exists"
    if path.is_symlink():
        return "refusing to clean a symlink"
    if target.safety_root is None:
        return "target is missing a safety root"

    try:
        resolved = path.resolve()
        safety_root = target.safety_root.expanduser().resolve()
    except OSError as exc:
        return str(exc)

    if str(resolved) == "/" or resolved.name in DANGEROUS_NAMES:
        return "refusing to clean dangerous path"
    if str(safety_root) == "/" or safety_root.name in DANGEROUS_NAMES:
        return "refusing to use dangerous safety root"
    if not _is_relative_to_or_equal(resolved, safety_root):
        return "target is outside its safety root"
    suffix_error = validate_category_path(target, resolved, safety_root)
    if suffix_error:
        return suffix_error
    if target.delete_mode == "tree" and target.category == "node-modules":
        if path.name != "node_modules":
            return "refusing to clean a non-node_modules tree"
    if target.delete_mode == "contents" and not path.is_dir():
        return "contents mode requires a directory"
    if target.delete_mode == "simctl-device-set" and not path.is_dir():
        return "simctl device-set mode requires a directory"

    return ""


def validate_category_path(target: ScanTarget, resolved: Path, safety_root: Path) -> str:
    try:
        parts = resolved.relative_to(safety_root).parts
    except ValueError:
        return "target is outside its safety root"

    if target.category == "node-modules":
        if resolved.name != "node_modules":
            return "refusing to clean a non-node_modules tree"
        return ""

    allowed_suffixes = FIXED_CATEGORY_SUFFIXES.get(target.category)
    if allowed_suffixes and tuple(parts) in allowed_suffixes:
        return ""

    if target.category == "simulator-caches" and _looks_like_simulator_device_cache(parts):
        return ""

    return "target path does not match a known cleanable cache location"


def _remove_contents(path: Path) -> None:
    if path.is_symlink() or not path.is_dir():
        raise OSError("refusing to clean contents of a non-directory or symlink")
    for child in path.iterdir():
        _remove_path(child)


def _remove_path(path: Path) -> None:
    try:
        mode = os.lstat(path).st_mode
    except OSError:
        return

    if stat.S_ISLNK(mode) or stat.S_ISREG(mode):
        path.unlink()
    elif stat.S_ISDIR(mode):
        if not shutil.rmtree.avoids_symlink_attacks:
            raise OSError("refusing directory deletion without symlink-safe rmtree support")
        shutil.rmtree(path)


def _is_relative_to_or_equal(path: Path, root: Path) -> bool:
    if path == root:
        return True
    return root in path.parents


def _looks_like_simulator_device_cache(parts: tuple[str, ...]) -> bool:
    return (
        len(parts) == 8
        and parts[0:4] == ("Library", "Developer", "CoreSimulator", "Devices")
        and _looks_like_uuid(parts[4])
        and parts[5:] == ("data", "Library", "Caches")
    )


def _looks_like_uuid(value: str) -> bool:
    groups = value.split("-")
    lengths = [8, 4, 4, 4, 12]
    return len(groups) == 5 and all(
        len(group) == length and all(char in "0123456789abcdefABCDEF" for char in group)
        for group, length in zip(groups, lengths)
    )


def _result(target: ScanTarget, dry_run: bool, removed: bool, error: str = "") -> CleanResult:
    return CleanResult(
        category=target.category,
        label=target.label,
        path=target.path,
        size_bytes=target.size_bytes,
        dry_run=dry_run,
        removed=removed,
        error=error,
    )
