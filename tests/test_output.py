import json
import unittest
from pathlib import Path

from mac_dev_clean.model import CleanResult, ScanTarget
from mac_dev_clean.output import render_clean_table, render_scan_table, scan_report_json


class OutputTests(unittest.TestCase):
    def test_render_scan_table_suggests_top_cleanable_dry_runs(self):
        items = [
            ScanTarget(
                category="xcode-device-support",
                label="Xcode iOS DeviceSupport",
                path=Path("/tmp/home/Library/Developer/Xcode/iOS DeviceSupport"),
                size_bytes=12 * 1024 * 1024 * 1024,
                modified_at=None,
                cleanable=True,
                delete_mode="contents",
            ),
            ScanTarget(
                category="browser-cache",
                label="Google browser caches",
                path=Path("/tmp/home/Library/Caches/Google"),
                size_bytes=2 * 1024 * 1024 * 1024,
                modified_at=None,
                cleanable=True,
                delete_mode="contents",
            ),
            ScanTarget(
                category="xcode-archives",
                label="Xcode Archives",
                path=Path("/tmp/home/Library/Developer/Xcode/Archives"),
                size_bytes=1024 * 1024 * 1024,
                modified_at=None,
                cleanable=False,
                delete_mode="none",
            ),
        ]

        output = render_scan_table(items)

        self.assertIn("Cleanable:    14.0 GB across 2 item(s)", output)
        self.assertIn("Review only:  1.0 GB across 1 item(s)", output)
        self.assertIn("Quick wins\n----------", output)
        self.assertIn("mac-dev-clean clean --xcode-device-support --dry-run", output)
        self.assertIn("mac-dev-clean clean --browser-caches --dry-run", output)
        self.assertNotIn("xcode-archives --dry-run", output)

    def test_scan_report_json_includes_cleanable_and_report_only_totals(self):
        payload = json.loads(
            scan_report_json(
                [
                    ScanTarget(
                        category="brew-cache",
                        label="Homebrew cache",
                        path=Path("/tmp/home/Library/Caches/Homebrew"),
                        size_bytes=10,
                        modified_at=None,
                        cleanable=True,
                        delete_mode="contents",
                    ),
                    ScanTarget(
                        category="docker",
                        label="Docker Desktop VM data",
                        path=Path("/tmp/home/Library/Containers/com.docker.docker/Data/vms"),
                        size_bytes=25,
                        modified_at=None,
                        cleanable=False,
                        delete_mode="none",
                    ),
                ]
            )
        )

        self.assertEqual(payload["total_bytes"], 35)
        self.assertEqual(payload["cleanable_total_bytes"], 10)
        self.assertEqual(payload["report_only_total_bytes"], 25)
        self.assertEqual(payload["recommendations"][0]["command"], "mac-dev-clean clean --brew-cache --dry-run")

    def test_xctest_clone_size_is_presented_as_shared_unknown(self):
        target = ScanTarget(
            category="xcode-test-devices",
            label="XCTest simulator clones",
            path=Path("/tmp/home/Library/Developer/XCTestDevices"),
            size_bytes=759 * 1024 * 1024 * 1024,
            modified_at=None,
            cleanable=True,
            delete_mode="simctl-device-set",
        )

        output = render_scan_table([target])

        self.assertIn("shared/unknown", output)
        self.assertNotIn("759.0 GB", output)

    def test_xctest_cleanup_reports_async_delete_request(self):
        result = CleanResult(
            category="xcode-test-devices",
            label="XCTest simulator clones",
            path=Path("/tmp/home/Library/Developer/XCTestDevices"),
            size_bytes=0,
            dry_run=False,
            removed=True,
        )

        output = render_clean_table([result])

        self.assertIn("delete requested", output)
        self.assertIn("APFS may reclaim shared blocks in the background", output)

    def test_report_only_items_include_review_guidance(self):
        target = ScanTarget(
            category="icloud-candidate",
            label="Codex generated images",
            path=Path("/tmp/home/.codex/generated_images"),
            size_bytes=1024 * 1024 * 1024,
            modified_at=None,
            cleanable=False,
            delete_mode="none",
            note="Copy finished images to iCloud Drive, then Remove Download in Finder.",
        )

        output = render_scan_table([target])

        self.assertIn("Review-only items (1)", output)
        self.assertIn("Remove Download in Finder", output)

    def test_human_scan_output_uses_spaced_two_line_entries(self):
        items = [
            ScanTarget(
                category="browser-cache",
                label="Chrome model",
                path=Path.home() / "Library/Application Support/Google/Chrome/Model",
                size_bytes=4 * 1024 * 1024 * 1024,
                modified_at=None,
                cleanable=True,
                delete_mode="contents",
            ),
            ScanTarget(
                category="editor-cache",
                label="Cursor cache",
                path=Path.home() / "Library/Application Support/Cursor/Cache",
                size_bytes=100 * 1024 * 1024,
                modified_at=None,
                cleanable=True,
                delete_mode="contents",
            ),
        ]

        output = render_scan_table(items)

        self.assertIn("Cleanable items (2)\n-------------------", output)
        self.assertIn("\n    Path: ~/Library/Application Support/Google/Chrome/Model", output)
        self.assertIn("Model\n\n  editor-cache", output)


if __name__ == "__main__":
    unittest.main()
