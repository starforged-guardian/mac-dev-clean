"""Tests for the GitHub release helper."""

from datetime import date
import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/release.py"
SPEC = importlib.util.spec_from_file_location("release_script", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
release_script = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release_script)


class ReleaseScriptTests(unittest.TestCase):
    def test_next_version_supports_standard_bumps(self):
        self.assertEqual(release_script.next_version("1.2.3", "patch"), "1.2.4")
        self.assertEqual(release_script.next_version("1.2.3", "minor"), "1.3.0")
        self.assertEqual(release_script.next_version("1.2.3", "major"), "2.0.0")
        self.assertEqual(release_script.next_version("1.2.3", "1.4.0"), "1.4.0")

    def test_next_version_rejects_invalid_or_older_versions(self):
        for requested in ("banana", "1.2", "1.2.3-beta", "1.2.3", "1.1.9"):
            with self.subTest(requested=requested):
                with self.assertRaises(release_script.ReleaseError):
                    release_script.next_version("1.2.3", requested)

    def test_read_declared_version_requires_matching_metadata(self):
        self.assertEqual(
            release_script.read_declared_version(
                '[project]\nversion = "0.5.0"\n', '__version__ = "0.5.0"\n'
            ),
            "0.5.0",
        )
        with self.assertRaises(release_script.ReleaseError):
            release_script.read_declared_version(
                '[project]\nversion = "0.5.0"\n', '__version__ = "0.4.0"\n'
            )

    def test_native_versions_must_match_package_metadata(self):
        release_script.require_native_version(
            "0.5.0",
            '        MARKETING_VERSION: "0.5.0"\n',
            "\t\t\t\tMARKETING_VERSION = 0.5.0;\n"
            "\t\t\t\tMARKETING_VERSION = 0.5.0;\n",
        )

        with self.assertRaises(release_script.ReleaseError):
            release_script.require_native_version(
                "0.5.0",
                '        MARKETING_VERSION: "0.4.0"\n',
                "\t\t\t\tMARKETING_VERSION = 0.5.0;\n",
            )

    def test_all_generated_xcode_versions_are_updated(self):
        original = (
            "\t\t\t\tMARKETING_VERSION = 0.5.0;\n"
            "\t\t\t\tMARKETING_VERSION = 0.5.0;\n"
        )

        updated = release_script.replace_all_declared_versions(
            original,
            release_script.XCODE_PROJECT_VERSION_PATTERN,
            "0.5.0",
            "0.5.1",
        )

        self.assertEqual(updated.count("MARKETING_VERSION = 0.5.1;"), 2)

    def test_update_changelog_dates_unreleased_entries(self):
        changelog = (
            "# Changelog\n\n"
            "## Unreleased\n\n"
            "- Added release automation.\n\n"
            "## 0.5.0 - 2026-07-11\n\n"
            "- Previous work.\n"
        )

        updated = release_script.update_changelog(
            changelog, "0.5.1", date(2026, 7, 12).isoformat()
        )

        self.assertIn(
            "## Unreleased\n\n## 0.5.1 - 2026-07-12\n\n"
            "- Added release automation.",
            updated,
        )
        self.assertEqual(updated.count("- Added release automation."), 1)
        self.assertIn("## 0.5.0 - 2026-07-11", updated)

    def test_update_changelog_requires_release_notes(self):
        with self.assertRaises(release_script.ReleaseError):
            release_script.update_changelog(
                "# Changelog\n\n## Unreleased\n\n## 0.5.0 - 2026-07-11\n",
                "0.5.1",
                "2026-07-12",
            )


if __name__ == "__main__":
    unittest.main()
