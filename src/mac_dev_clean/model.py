from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Optional


@dataclass(frozen=True)
class ScanTarget:
    category: str
    label: str
    path: Path
    size_bytes: int
    modified_at: Optional[datetime]
    cleanable: bool
    delete_mode: str
    note: str = ""

    def to_dict(self) -> Dict[str, object]:
        return {
            "category": self.category,
            "label": self.label,
            "path": str(self.path),
            "size_bytes": self.size_bytes,
            "size": human_bytes(self.size_bytes),
            "modified_at": self.modified_at.astimezone(timezone.utc).isoformat()
            if self.modified_at
            else None,
            "cleanable": self.cleanable,
            "delete_mode": self.delete_mode,
            "note": self.note,
        }


@dataclass(frozen=True)
class CleanResult:
    category: str
    label: str
    path: Path
    size_bytes: int
    dry_run: bool
    removed: bool
    error: str = ""

    def to_dict(self) -> Dict[str, object]:
        return {
            "category": self.category,
            "label": self.label,
            "path": str(self.path),
            "size_bytes": self.size_bytes,
            "size": human_bytes(self.size_bytes),
            "dry_run": self.dry_run,
            "removed": self.removed,
            "error": self.error,
        }


def human_bytes(size: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB", "PB"]
    value = float(size)
    for unit in units:
        if abs(value) < 1024 or unit == units[-1]:
            if unit == "B":
                return f"{int(value)} {unit}"
            return f"{value:.1f} {unit}"
        value /= 1024

