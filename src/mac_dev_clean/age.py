from __future__ import annotations

import re
from datetime import timedelta


_AGE_RE = re.compile(r"^\s*(\d+)\s*([smhdw])\s*$", re.IGNORECASE)


def parse_age(value: str) -> timedelta:
    match = _AGE_RE.match(value)
    if not match:
        raise ValueError("age must look like 30d, 12h, 2w, 45m, or 10s")

    amount = int(match.group(1))
    unit = match.group(2).lower()
    if amount <= 0:
        raise ValueError("age must be greater than zero")

    if unit == "s":
        return timedelta(seconds=amount)
    if unit == "m":
        return timedelta(minutes=amount)
    if unit == "h":
        return timedelta(hours=amount)
    if unit == "d":
        return timedelta(days=amount)
    if unit == "w":
        return timedelta(weeks=amount)

    raise ValueError("unsupported age unit")

