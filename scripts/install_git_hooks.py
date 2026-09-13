#!/usr/bin/env python3
"""Activate this repository's versioned Git hooks without clobbering custom hooks."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
HOOKS_PATH = ".githooks"


def git_config(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "config", *args],
        cwd=REPO_ROOT,
        check=check,
        capture_output=True,
        text=True,
    )


def main() -> int:
    current_result = git_config("--get", "core.hooksPath", check=False)
    if current_result.returncode not in (0, 1):
        message = current_result.stderr.strip() or "Could not read core.hooksPath."
        print(message, file=sys.stderr)
        return current_result.returncode

    current = current_result.stdout.strip()
    if current and current != HOOKS_PATH:
        print(
            f"Refusing to replace existing core.hooksPath={current}. "
            "Review and merge the hooks manually.",
            file=sys.stderr,
        )
        return 1

    install_result = git_config("core.hooksPath", HOOKS_PATH, check=False)
    if install_result.returncode != 0:
        message = install_result.stderr.strip() or "Could not set core.hooksPath."
        print(message, file=sys.stderr)
        return install_result.returncode

    print(f"Installed repository Git hooks from {HOOKS_PATH}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
