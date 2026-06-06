from __future__ import annotations

import shutil
from pathlib import Path
from typing import Iterable, List

from .model import CleanResult, ScanTarget


DANGEROUS_NAMES = {"", ".", ".."}


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
        else:
            return _result(
                target,
                dry_run=False,
                removed=False,
                error=f"unsupported delete mode: {target.delete_mode}",
            )
    except OSError as exc:
        return _result(target, dry_run=False, removed=False, error=str(exc))

    return _result(target, dry_run=False, removed=True)


def validate_target(target: ScanTarget) -> str:
    path = target.path
    if not target.cleanable:
        return "target is report-only"
    if target.delete_mode not in {"contents", "tree"}:
        return "target is not configured for deletion"
    if not path.exists():
        return "path no longer exists"
    if path.is_symlink():
        return "refusing to clean a symlink"

    try:
        resolved = path.resolve()
    except OSError as exc:
        return str(exc)

    if str(resolved) == "/" or resolved.name in DANGEROUS_NAMES:
        return "refusing to clean dangerous path"
    if target.delete_mode == "tree" and target.category == "node-modules":
        if path.name != "node_modules":
            return "refusing to clean a non-node_modules tree"
    if target.delete_mode == "contents" and not path.is_dir():
        return "contents mode requires a directory"

    return ""


def _remove_contents(path: Path) -> None:
    for child in path.iterdir():
        _remove_path(child)


def _remove_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


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

