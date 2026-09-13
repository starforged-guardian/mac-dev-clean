import unittest
from pathlib import Path

from mac_dev_clean.xcode_archives import (
    display_name_from_folder,
    looks_like_archive_date,
    looks_like_xcode_archive_parts,
)


class XcodeArchiveHelperTests(unittest.TestCase):
    def test_display_name_strips_xcode_organizer_timestamp(self):
        self.assertEqual(
            display_name_from_folder("Blackwing Vault 9-12-26, 9.17 PM.xcarchive"),
            "Blackwing Vault",
        )
        self.assertEqual(display_name_from_folder("App.xcarchive"), "App")

    def test_archive_date_folders_must_be_iso_dates(self):
        self.assertTrue(looks_like_archive_date("2026-09-12"))
        self.assertFalse(looks_like_archive_date("2026-9-12"))
        self.assertFalse(looks_like_archive_date("Archives"))

    def test_archive_path_shape_requires_dated_xcarchive(self):
        self.assertTrue(
            looks_like_xcode_archive_parts(
                (
                    "Library",
                    "Developer",
                    "Xcode",
                    "Archives",
                    "2026-09-12",
                    "App 9-12-26, 8.00 PM.xcarchive",
                )
            )
        )
        self.assertFalse(
            looks_like_xcode_archive_parts(
                ("Library", "Developer", "Xcode", "Archives", "2026-09-12", "App")
            )
        )
        self.assertFalse(
            looks_like_xcode_archive_parts(
                Path("/tmp/home/Documents/App.xcarchive").parts[-2:]
            )
        )


if __name__ == "__main__":
    unittest.main()
