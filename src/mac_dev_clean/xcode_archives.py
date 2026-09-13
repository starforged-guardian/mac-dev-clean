from __future__ import annotations

import os
import plistlib
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple


ARCHIVE_CATEGORY = "xcode-archives"
ARCHIVE_COPIES_CATEGORY = "xcode-archive-copies"
ARCHIVE_RELATIVE_PREFIX = ("Library", "Developer", "Xcode", "Archives")
_ARCHIVE_NAME_RE = re.compile(r"^(?P<name>.+?)\s+\d{1,2}-\d{1,2}-\d{2}")
_IDENTITY_NOISE_RE = re.compile(r"[\s_\-]+")


@dataclass(frozen=True)
class ArchiveRecord:
    path: Path
    identity: str
    name_key: str
    bundle_id: str
    display_name: str
    created_at: Optional[datetime]
    modified_at: Optional[datetime]

    @property
    def recency_key(self) -> Tuple[datetime, datetime, str]:
        oldest = datetime.min.replace(tzinfo=timezone.utc)
        return (
            self.created_at or oldest,
            self.modified_at or oldest,
            str(self.path),
        )


def discover_archives(archives_root: Path) -> List[ArchiveRecord]:
    root = archives_root.expanduser()
    if not root.is_dir() or root.is_symlink():
        return []

    records: List[ArchiveRecord] = []
    try:
        date_dirs = list(root.iterdir())
    except OSError:
        return []

    for date_dir in date_dirs:
        try:
            if date_dir.is_symlink() or not date_dir.is_dir():
                continue
        except OSError:
            continue
        if not looks_like_archive_date(date_dir.name):
            continue
        try:
            children = list(date_dir.iterdir())
        except OSError:
            continue
        for child in children:
            record = _record_from_path(child)
            if record is not None:
                records.append(record)
    return records


def classify_archives(
    records: Sequence[ArchiveRecord],
) -> Tuple[List[ArchiveRecord], List[ArchiveRecord]]:
    by_name: Dict[str, List[ArchiveRecord]] = {}
    for record in records:
        by_name.setdefault(record.name_key, []).append(record)

    latest: List[ArchiveRecord] = []
    older: List[ArchiveRecord] = []
    for group in by_name.values():
        for subgroup in _identity_subgroups(group):
            ordered = sorted(subgroup, key=lambda item: item.recency_key, reverse=True)
            latest.append(ordered[0])
            older.extend(ordered[1:])
    return latest, older


def _identity_subgroups(group: Sequence[ArchiveRecord]) -> List[List[ArchiveRecord]]:
    bundle_ids = {record.bundle_id for record in group if record.bundle_id}
    if len(bundle_ids) <= 1:
        return [list(group)]

    grouped: Dict[str, List[ArchiveRecord]] = {}
    unknown: List[ArchiveRecord] = []
    for record in group:
        if record.bundle_id:
            grouped.setdefault(record.bundle_id, []).append(record)
        else:
            unknown.append(record)
    subgroups = list(grouped.values())
    if len(subgroups) == 1:
        subgroups[0].extend(unknown)
    elif unknown:
        subgroups.append(unknown)
    return subgroups


def looks_like_archive_date(value: str) -> bool:
    if len(value) != 10:
        return False
    try:
        datetime.strptime(value, "%Y-%m-%d")
    except ValueError:
        return False
    return True


def looks_like_xcode_archive_parts(parts: Sequence[str]) -> bool:
    if len(parts) != 6:
        return False
    if tuple(parts[:4]) != ARCHIVE_RELATIVE_PREFIX:
        return False
    name = parts[5]
    return (
        looks_like_archive_date(parts[4])
        and name.endswith(".xcarchive")
        and len(name) > len(".xcarchive")
    )


def is_latest_xcode_archive(path: Path, safety_root: Path) -> bool:
    archives_root = safety_root.expanduser() / Path(*ARCHIVE_RELATIVE_PREFIX)
    latest, _older = classify_archives(discover_archives(archives_root))
    try:
        resolved = path.expanduser().resolve()
    except OSError:
        return False
    for record in latest:
        try:
            if record.path.resolve() == resolved:
                return True
        except OSError:
            continue
    return False


def display_name_from_folder(name: str) -> str:
    stem = name[: -len(".xcarchive")] if name.endswith(".xcarchive") else name
    match = _ARCHIVE_NAME_RE.match(stem)
    return match.group("name") if match else stem


def _record_from_path(path: Path) -> Optional[ArchiveRecord]:
    try:
        if path.is_symlink() or not path.is_dir():
            return None
    except OSError:
        return None
    if not path.name.endswith(".xcarchive") or path.name == ".xcarchive":
        return None

    identity, name_key, bundle_id, display_name, created_at = _archive_metadata(path)
    return ArchiveRecord(
        path=path,
        identity=identity,
        name_key=name_key,
        bundle_id=bundle_id,
        display_name=display_name,
        created_at=created_at,
        modified_at=_modified_time(path),
    )


def _archive_metadata(path: Path) -> Tuple[str, str, str, str, Optional[datetime]]:
    info = _load_plist(path / "Info.plist")
    properties = info.get("ApplicationProperties")
    bundle_id = ""
    if isinstance(properties, dict):
        bundle_id = str(properties.get("CFBundleIdentifier") or "").strip()
    name = str(info.get("Name") or info.get("SchemeName") or "").strip()
    display_name = name or display_name_from_folder(path.name)
    name_key = _compact_identity(display_name)
    identity = f"{bundle_id}|{name_key}" if bundle_id else f"name:{name_key}"
    return identity, name_key, bundle_id, display_name, _as_utc(info.get("CreationDate"))


def _compact_identity(value: str) -> str:
    return _IDENTITY_NOISE_RE.sub("", value).casefold()


def _load_plist(path: Path) -> Dict[str, object]:
    if not path.is_file() or path.is_symlink():
        return {}
    try:
        with path.open("rb") as handle:
            payload = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException, ValueError, TypeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def _as_utc(value: object) -> Optional[datetime]:
    if not isinstance(value, datetime):
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _modified_time(path: Path) -> Optional[datetime]:
    try:
        return datetime.fromtimestamp(os.stat(path, follow_symlinks=False).st_mtime, timezone.utc)
    except OSError:
        return None


