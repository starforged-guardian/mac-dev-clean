from datetime import datetime, timedelta, timezone
from pathlib import Path
from tempfile import TemporaryDirectory
import os
import unittest

from mac_dev_clean.cleaner import clean_target
from mac_dev_clean.scanner import find_node_modules, scan


class ScannerCleanerTests(unittest.TestCase):
    def test_scan_finds_fixed_cache_location(self):
        with TemporaryDirectory() as temp:
            home = Path(temp)
            cache = home / "Library/Developer/Xcode/DerivedData/App"
            cache.mkdir(parents=True)
            (cache / "artifact.o").write_bytes(b"x" * 1024)

            items = scan(home=home, cwd=home / "workspace", include_node_modules=False)

            categories = {item.category for item in items}
            self.assertIn("xcode-derived-data", categories)
            target = next(item for item in items if item.category == "xcode-derived-data")
            self.assertGreaterEqual(target.size_bytes, 1024)
            self.assertTrue(target.cleanable)

    def test_dry_run_does_not_delete_contents(self):
        with TemporaryDirectory() as temp:
            home = Path(temp)
            cache = home / "Library/Caches/Homebrew"
            cache.mkdir(parents=True)
            payload = cache / "bottle.tar.gz"
            payload.write_bytes(b"x")

            target = scan(home=home, cwd=home, include_node_modules=False)[0]
            result = clean_target(target, dry_run=True)

            self.assertFalse(result.removed)
            self.assertTrue(payload.exists())

    def test_clean_contents_preserves_parent_directory(self):
        with TemporaryDirectory() as temp:
            home = Path(temp)
            cache = home / "Library/Caches/Homebrew"
            cache.mkdir(parents=True)
            payload = cache / "bottle.tar.gz"
            payload.write_bytes(b"x")

            target = scan(home=home, cwd=home, include_node_modules=False)[0]
            result = clean_target(target)

            self.assertTrue(result.removed)
            self.assertTrue(cache.exists())
            self.assertFalse(payload.exists())

    def test_clean_refuses_symlink_target(self):
        with TemporaryDirectory() as temp:
            home = Path(temp)
            real_cache = home / "real-cache"
            real_cache.mkdir()
            link = home / "Library/Caches/Homebrew"
            link.parent.mkdir(parents=True)
            link.symlink_to(real_cache, target_is_directory=True)

            target = scan(home=home, cwd=home, include_node_modules=False)[0]
            result = clean_target(target)

            self.assertFalse(result.removed)
            self.assertIn("symlink", result.error)
            self.assertTrue(real_cache.exists())

    def test_find_node_modules_skips_nested_dependencies(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            nested = root / "app/node_modules/pkg/node_modules"
            nested.mkdir(parents=True)

            found = list(find_node_modules(root))

            self.assertEqual(found, [root / "app/node_modules"])

    def test_node_modules_older_than_filter(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            old_nm = root / "old-app/node_modules"
            new_nm = root / "new-app/node_modules"
            old_nm.mkdir(parents=True)
            new_nm.mkdir(parents=True)

            now = datetime(2026, 6, 6, tzinfo=timezone.utc)
            old_time = (now - timedelta(days=90)).timestamp()
            new_time = (now - timedelta(days=5)).timestamp()
            os.utime(old_nm, (old_time, old_time))
            os.utime(new_nm, (new_time, new_time))

            items = scan(
                home=root,
                cwd=root,
                search_roots=[root],
                include_node_modules=True,
                node_modules_older_than=timedelta(days=60),
                now=now,
            )

            paths = {item.path for item in items if item.category == "node-modules"}
            self.assertEqual(paths, {old_nm})


if __name__ == "__main__":
    unittest.main()
