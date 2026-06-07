import json
import unittest
from pathlib import Path

from mac_dev_clean.model import ScanTarget
from mac_dev_clean.output import render_scan_table, scan_report_json


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

        self.assertIn("Potential cleanup: 14.0 GB cleanable | 1.0 GB report-only", output)
        self.assertIn("Quick wins:", output)
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


if __name__ == "__main__":
    unittest.main()
