#!/usr/bin/env python3
"""Prepare and publish a mac-dev-clean GitHub release."""

from __future__ import annotations

import argparse
from datetime import date
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Dict, Optional, Sequence


ROOT = Path(__file__).resolve().parents[1]
PYPROJECT = ROOT / "pyproject.toml"
PACKAGE_INIT = ROOT / "src/mac_dev_clean/__init__.py"
CHANGELOG = ROOT / "CHANGELOG.md"
XCODE_SPEC = ROOT / "macos/project.yml"
XCODE_PROJECT = ROOT / "macos/MacDevClean.xcodeproj/project.pbxproj"
VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")
PYPROJECT_VERSION_PATTERN = re.compile(r'^version = "(\d+\.\d+\.\d+)"$', re.MULTILINE)
PACKAGE_VERSION_PATTERN = re.compile(r'^__version__ = "(\d+\.\d+\.\d+)"$', re.MULTILINE)
XCODE_SPEC_VERSION_PATTERN = re.compile(
    r'^        MARKETING_VERSION: "(\d+\.\d+\.\d+)"$', re.MULTILINE
)
XCODE_PROJECT_VERSION_PATTERN = re.compile(
    r'^\s+MARKETING_VERSION = (\d+\.\d+\.\d+);$', re.MULTILINE
)


class ReleaseError(RuntimeError):
    """A release precondition or preparation step failed."""


def read_declared_version(pyproject_text: str, package_text: str) -> str:
    """Return the version shared by the two package metadata files."""
    pyproject_match = PYPROJECT_VERSION_PATTERN.search(pyproject_text)
    package_match = PACKAGE_VERSION_PATTERN.search(package_text)
    if pyproject_match is None or package_match is None:
        raise ReleaseError("Could not find both package version declarations.")
    if pyproject_match.group(1) != package_match.group(1):
        raise ReleaseError(
            "Version mismatch: pyproject.toml has "
            f"{pyproject_match.group(1)}, while __init__.py has "
            f"{package_match.group(1)}."
        )
    return pyproject_match.group(1)


def require_native_version(
    expected: str, xcode_spec_text: str, xcode_project_text: str
) -> None:
    """Require generated native-app metadata to match the Python package."""
    spec_match = XCODE_SPEC_VERSION_PATTERN.search(xcode_spec_text)
    project_versions = XCODE_PROJECT_VERSION_PATTERN.findall(xcode_project_text)
    if spec_match is None or not project_versions:
        raise ReleaseError("Could not find native app version declarations.")
    declared = {spec_match.group(1), *project_versions}
    if declared != {expected}:
        raise ReleaseError(
            "Version mismatch: Python metadata has "
            f"{expected}, while native app metadata has {', '.join(sorted(declared))}."
        )


def next_version(current: str, requested: str) -> str:
    """Resolve patch/minor/major or an explicit semantic version."""
    current_parts = tuple(int(part) for part in current.split("."))
    if requested == "patch":
        target_parts = (current_parts[0], current_parts[1], current_parts[2] + 1)
    elif requested == "minor":
        target_parts = (current_parts[0], current_parts[1] + 1, 0)
    elif requested == "major":
        target_parts = (current_parts[0] + 1, 0, 0)
    elif VERSION_PATTERN.fullmatch(requested):
        target_parts = tuple(int(part) for part in requested.split("."))
    else:
        raise ReleaseError(
            "Version must be patch, minor, major, or an explicit X.Y.Z version."
        )

    if target_parts <= current_parts:
        raise ReleaseError(
            f"Requested version {'.'.join(map(str, target_parts))} must be newer "
            f"than {current}."
        )
    return ".".join(map(str, target_parts))


def update_changelog(text: str, version: str, release_date: str) -> str:
    """Move the non-empty Unreleased section into a dated release section."""
    unreleased = re.search(r"^## Unreleased\s*$", text, re.MULTILINE)
    if unreleased is None:
        raise ReleaseError("CHANGELOG.md is missing an '## Unreleased' section.")

    next_heading = re.search(
        r"^## \d+\.\d+\.\d+(?:\s+-\s+\d{4}-\d{2}-\d{2})?\s*$",
        text[unreleased.end() :],
        re.MULTILINE,
    )
    if next_heading is None:
        section_end = len(text)
    else:
        section_end = unreleased.end() + next_heading.start()

    entries = text[unreleased.end() : section_end].strip()
    if not entries:
        raise ReleaseError(
            "CHANGELOG.md has no entries under '## Unreleased'; add release notes first."
        )

    remainder = text[section_end:].lstrip("\n")
    release_section = (
        f"## Unreleased\n\n## {version} - {release_date}\n\n{entries}\n\n"
    )
    return text[: unreleased.start()] + release_section + remainder


def replace_declared_version(text: str, pattern: re.Pattern[str], old: str, new: str) -> str:
    """Replace one known version declaration and fail on unexpected content."""
    replacement = lambda match: match.group(0).replace(old, new, 1)
    updated, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise ReleaseError(f"Could not replace version {old} with {new}.")
    return updated


def replace_all_declared_versions(
    text: str, pattern: re.Pattern[str], old: str, new: str
) -> str:
    """Replace one or more matching declarations after validating their value."""
    matches = list(pattern.finditer(text))
    if not matches or any(match.group(1) != old for match in matches):
        raise ReleaseError(f"Could not replace every version {old} with {new}.")
    return pattern.sub(lambda match: match.group(0).replace(old, new, 1), text)


def command(
    args: Sequence[str],
    *,
    capture: bool = False,
    env: Optional[Dict[str, str]] = None,
) -> str:
    """Run a checked command from the repository root."""
    result = subprocess.run(
        list(args),
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        env=env,
    )
    return result.stdout.strip() if capture and result.stdout else ""


def require_command(name: str) -> None:
    if shutil.which(name) is None:
        raise ReleaseError(f"Required command '{name}' is not installed.")


def preflight(version: str) -> None:
    """Ensure the release can be created safely from an up-to-date main branch."""
    require_command("git")
    require_command("gh")
    require_command("swift")
    require_command("xcodebuild")

    repository_root = Path(command(["git", "rev-parse", "--show-toplevel"], capture=True))
    if repository_root.resolve() != ROOT:
        raise ReleaseError(f"Run this script from the {ROOT} repository.")

    status = command(["git", "status", "--porcelain"], capture=True)
    if status:
        raise ReleaseError("The working tree is not clean; commit or stash changes first.")

    branch = command(["git", "branch", "--show-current"], capture=True)
    if branch != "main":
        raise ReleaseError(f"Releases must run from main, not '{branch or 'detached HEAD'}'.")

    command(["gh", "auth", "status"])
    command(["git", "fetch", "origin", "main", "--tags"])

    head = command(["git", "rev-parse", "HEAD"], capture=True)
    remote_main = command(["git", "rev-parse", "origin/main"], capture=True)
    if head != remote_main:
        raise ReleaseError("Local main must exactly match origin/main before releasing.")

    tag = command(
        ["git", "ls-remote", "--tags", "origin", f"refs/tags/{version}"],
        capture=True,
    )
    if tag:
        raise ReleaseError(f"Tag {version} already exists on GitHub.")


def prepare_files(current: str, version: str, release_date: str) -> None:
    """Write the version and changelog updates for a release commit."""
    pyproject_text = PYPROJECT.read_text(encoding="utf-8")
    package_text = PACKAGE_INIT.read_text(encoding="utf-8")
    changelog_text = CHANGELOG.read_text(encoding="utf-8")
    xcode_spec_text = XCODE_SPEC.read_text(encoding="utf-8")
    xcode_project_text = XCODE_PROJECT.read_text(encoding="utf-8")

    PYPROJECT.write_text(
        replace_declared_version(
            pyproject_text, PYPROJECT_VERSION_PATTERN, current, version
        ),
        encoding="utf-8",
    )
    PACKAGE_INIT.write_text(
        replace_declared_version(
            package_text, PACKAGE_VERSION_PATTERN, current, version
        ),
        encoding="utf-8",
    )
    XCODE_SPEC.write_text(
        replace_declared_version(
            xcode_spec_text, XCODE_SPEC_VERSION_PATTERN, current, version
        ),
        encoding="utf-8",
    )
    XCODE_PROJECT.write_text(
        replace_all_declared_versions(
            xcode_project_text, XCODE_PROJECT_VERSION_PATTERN, current, version
        ),
        encoding="utf-8",
    )
    CHANGELOG.write_text(
        update_changelog(changelog_text, version, release_date),
        encoding="utf-8",
    )


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Increment the package version, finalize the changelog, run tests, "
            "push main, and publish a GitHub release."
        )
    )
    parser.add_argument(
        "version",
        nargs="?",
        default="patch",
        help="patch (default), minor, major, or an explicit X.Y.Z version",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="validate the version and changelog, then print the planned release",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="publish without the interactive confirmation",
    )
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    try:
        pyproject_text = PYPROJECT.read_text(encoding="utf-8")
        package_text = PACKAGE_INIT.read_text(encoding="utf-8")
        current = read_declared_version(pyproject_text, package_text)
        require_native_version(
            current,
            XCODE_SPEC.read_text(encoding="utf-8"),
            XCODE_PROJECT.read_text(encoding="utf-8"),
        )
        version = next_version(current, args.version)
        release_date = date.today().isoformat()

        # Validate the changelog before doing network or repository checks.
        update_changelog(
            CHANGELOG.read_text(encoding="utf-8"), version, release_date
        )

        print(f"Current version: {current}")
        print(f"Release version: {version}")
        print("Actions: update metadata and changelog, test, commit, push, release")

        if args.dry_run:
            print("Dry run complete; no files or remote state changed.")
            return 0

        preflight(version)
        if not args.yes:
            response = input(f"Publish mac-dev-clean {version}? [y/N] ").strip().lower()
            if response not in {"y", "yes"}:
                print("Release cancelled.")
                return 1

        prepare_files(current, version, release_date)

        test_env = os.environ.copy()
        test_env["PYTHONPATH"] = str(ROOT / "src")
        test_env.setdefault(
            "PYTHONPYCACHEPREFIX", "/private/tmp/mac-dev-clean-pycache"
        )
        command(
            [sys.executable, "-m", "unittest", "discover", "-s", "tests"],
            env=test_env,
        )
        command(["swift", "test", "--package-path", "macos"])
        command(
            [
                "xcodebuild",
                "-project",
                "macos/MacDevClean.xcodeproj",
                "-scheme",
                "MacDevCleanApp",
                "-configuration",
                "Release",
                "-destination",
                "generic/platform=macOS",
                "CODE_SIGNING_ALLOWED=NO",
                "build",
            ]
        )
        command(["git", "diff", "--check"])
        command(
            [
                "git",
                "add",
                str(PYPROJECT),
                str(PACKAGE_INIT),
                str(CHANGELOG),
                str(XCODE_SPEC),
                str(XCODE_PROJECT),
            ]
        )
        command(["git", "commit", "-m", f"Release {version}"])
        command(["git", "push", "origin", "main"])
        command(
            [
                "gh",
                "release",
                "create",
                version,
                "--target",
                "main",
                "--title",
                f"mac-dev-clean {version}",
                "--generate-notes",
                "--latest",
            ]
        )
        command(["git", "fetch", "origin", "--tags"])
        url = command(
            ["gh", "release", "view", version, "--json", "url", "--jq", ".url"],
            capture=True,
        )
        print(f"Published {version}: {url}")
        return 0
    except (ReleaseError, OSError, subprocess.CalledProcessError) as error:
        print(f"release: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
