from datetime import datetime, timedelta, timezone
from pathlib import Path
from tempfile import TemporaryDirectory
import os
import unittest
from unittest.mock import patch

from mac_dev_clean.cleaner import clean_target
from mac_dev_clean.model import ScanTarget
from mac_dev_clean.scanner import _location_measurement, find_node_modules, scan
from mac_dev_clean.sim_prune import Device, Inventory


LARGE_PAYLOAD_BYTES = 2 * 1024 * 1024


class ScannerCleanerTests(unittest.TestCase):
    def test_scan_finds_fixed_cache_location(self):
        with TemporaryDirectory() as temp:
            home = Path(temp)
            cache = home / "Library/Developer/Xcode/DerivedData/App"
            cache.mkdir(parents=True)
            (cache / "artifact.o").write_bytes(b"x" * LARGE_PAYLOAD_BYTES)

            items = scan(home=home, cwd=home / "workspace", include_node_modules=False)

            categories = {item.category for item in items}
            self.assertIn("xcode-derived-data", categories)
            target = next(item for item in items if item.category == "xcode-derived-data")
            self.assertGreaterEqual(target.size_bytes, 1024)
            self.assertTrue(target.cleanable)

    def test_scan_can_limit_work_to_selected_categories(self):
        with TemporaryDirectory() as temp:
            home = Path(temp)
            derived_data = home / "Library/Developer/Xcode/DerivedData/App"
            browser_cache = home / "Library/Caches/Google/Chrome"
            derived_data.mkdir(parents=True)
            browser_cache.mkdir(parents=True)
            (derived_data / "artifact.o").write_bytes(b"x" * LARGE_PAYLOAD_BYTES)
            (browser_cache / "cache.bin").write_bytes(b"x" * LARGE_PAYLOAD_BYTES)

            items = scan(
                home=home,
                cwd=home,
                include_node_modules=False,
                categories={"xcode-derived-data"},
            )

            self.assertEqual({item.category for item in items}, {"xcode-derived-data"})

    def test_dry_run_does_not_delete_contents(self):
        with TemporaryDirectory() as temp:
            home = Path(temp)
            cache = home / "Library/Caches/Homebrew"
            cache.mkdir(parents=True)
            payload = cache / "bottle.tar.gz"
            payload.write_bytes(b"x" * LARGE_PAYLOAD_BYTES)

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
            payload.write_bytes(b"x" * LARGE_PAYLOAD_BYTES)

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
            target = ScanTarget(
                category="brew-cache",
                label="Homebrew cache",
                path=link,
                size_bytes=1,
                modified_at=None,
                cleanable=True,
                delete_mode="contents",
                safety_root=home,
            )
            result = clean_target(target)

            self.assertFalse(result.removed)
            self.assertIn("symlink", result.error)
            self.assertTrue(real_cache.exists())

    def test_scan_skips_tiny_cleanable_cache_locations(self):
        with TemporaryDirectory() as temp:
            home = Path(temp)
            cache = home / "Library/Developer/CoreSimulator/Caches"
            cache.mkdir(parents=True)
            (cache / "tiny-cache-marker").write_bytes(b"x" * 64)

            items = scan(home=home, cwd=home, include_node_modules=False)

            self.assertEqual(items, [])

    def test_scan_finds_xcode_device_support_and_archives(self):
        with TemporaryDirectory() as temp:
            home = Path(temp)
            support = home / "Library/Developer/Xcode/iOS DeviceSupport/iPhone 26.5"
            support.mkdir(parents=True)
            symbol_cache = support / "Symbols"
            symbol_cache.write_bytes(b"x" * LARGE_PAYLOAD_BYTES)

            archive = home / "Library/Developer/Xcode/Archives/2026-06-07/App.xcarchive"
            archive.mkdir(parents=True)
            (archive / "Info.plist").write_text("archive")

            items = scan(home=home, cwd=home, include_node_modules=False)

            support_target = next(item for item in items if item.category == "xcode-device-support")
            archive_target = next(item for item in items if item.category == "xcode-archives")
            self.assertTrue(support_target.cleanable)
            self.assertFalse(archive_target.cleanable)

            result = clean_target(support_target)

            self.assertTrue(result.removed)
            self.assertTrue(support_target.path.exists())
            self.assertFalse(symbol_cache.exists())
            self.assertTrue(archive.exists())

    def test_scan_finds_xcode_device_logs_and_test_device_clones(self):
        with TemporaryDirectory() as temp:
            home = Path(temp)
            device_logs = home / "Library/Developer/Xcode/DeviceLogs/iPhone/logs"
            test_devices = home / "Library/Developer/XCTestDevices/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
            device_logs.mkdir(parents=True)
            test_devices.mkdir(parents=True)
            (device_logs / "device.log").write_bytes(b"x" * LARGE_PAYLOAD_BYTES)
            (test_devices / "device.plist").write_bytes(b"x" * LARGE_PAYLOAD_BYTES)

            items = scan(home=home, cwd=home, include_node_modules=False)

            categories = {item.category for item in items}
            self.assertIn("xcode-device-logs", categories)
            self.assertIn("xcode-test-devices", categories)
            clone_target = next(item for item in items if item.category == "xcode-test-devices")
            self.assertEqual(clone_target.delete_mode, "simctl-device-set")

    def test_default_xctest_device_set_does_not_report_logical_clone_size_as_disk_use(self):
        device_set = Path.home() / "Library/Developer/XCTestDevices"
        device = Device(
            runtime_identifier="com.apple.CoreSimulator.SimRuntime.iOS-26-5",
            name="Clone 1 of iPhone 17 Pro",
            udid="AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            state="Shutdown",
            is_available=True,
            last_booted_at=None,
            data_size_bytes=4 * 1024 * 1024 * 1024,
            log_size_bytes=0,
        )

        with patch(
            "mac_dev_clean.scanner.load_device_set_inventory",
            return_value=Inventory(devices=[device], runtimes=[]),
        ):
            size, include_when_small = _location_measurement(
                device_set, "xcode-test-devices"
            )

        self.assertEqual(size, 0)
        self.assertTrue(include_when_small)

    def test_clean_xcode_test_devices_uses_simctl_device_set(self):
        with TemporaryDirectory() as temp:
            home = Path(temp)
            device_set = home / "Library/Developer/XCTestDevices"
            device_set.mkdir(parents=True)
            target = ScanTarget(
                category="xcode-test-devices",
                label="XCTest simulator clones",
                path=device_set,
                size_bytes=LARGE_PAYLOAD_BYTES,
                modified_at=None,
                cleanable=True,
                delete_mode="simctl-device-set",
                safety_root=home,
            )
            device = Device(
                runtime_identifier="com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                name="Clone 1 of iPhone 17 Pro",
                udid="AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
                state="Shutdown",
                is_available=True,
                last_booted_at=None,
                data_size_bytes=LARGE_PAYLOAD_BYTES,
                log_size_bytes=0,
            )
            inventory = Inventory(devices=[device], runtimes=[])

            with patch(
                "mac_dev_clean.cleaner.load_device_set_inventory", return_value=inventory
            ) as load_inventory, patch(
                "mac_dev_clean.cleaner.delete_test_clones"
            ) as delete_clones:
                result = clean_target(target)

            self.assertTrue(result.removed)
            load_inventory.assert_called_once_with(device_set)
            delete_clones.assert_called_once_with(inventory, device_set)

    def test_scan_finds_package_browser_and_report_only_tool_caches(self):
        with TemporaryDirectory() as temp:
            home = Path(temp)
            pnpm = home / "Library/pnpm/store/v3/files"
            browser = home / "Library/Caches/Google/Chrome/Default/Cache"
            codex_runtime = home / ".cache/codex-runtimes/python"
            pnpm.mkdir(parents=True)
            browser.mkdir(parents=True)
            codex_runtime.mkdir(parents=True)
            (pnpm / "pkg.bin").write_bytes(b"x" * LARGE_PAYLOAD_BYTES)
            (browser / "cache.bin").write_bytes(b"x" * LARGE_PAYLOAD_BYTES)
            (codex_runtime / "runtime.txt").write_text("runtime")

            items = scan(home=home, cwd=home, include_node_modules=False)

            categories = {item.category for item in items}
            self.assertIn("pnpm-cache", categories)
            self.assertIn("browser-cache", categories)
            self.assertIn("dev-tool-cache", categories)
            self.assertTrue(next(item for item in items if item.category == "pnpm-cache").cleanable)
            self.assertTrue(next(item for item in items if item.category == "browser-cache").cleanable)
            self.assertFalse(next(item for item in items if item.category == "dev-tool-cache").cleanable)

    def test_clean_refuses_target_without_safety_root(self):
        with TemporaryDirectory() as temp:
            home = Path(temp)
            cache = home / "Library/Caches/Homebrew"
            cache.mkdir(parents=True)
            payload = cache / "bottle.tar.gz"
            payload.write_bytes(b"x")
            target = ScanTarget(
                category="brew-cache",
                label="Homebrew cache",
                path=cache,
                size_bytes=1,
                modified_at=None,
                cleanable=True,
                delete_mode="contents",
            )

            result = clean_target(target)

            self.assertFalse(result.removed)
            self.assertIn("safety root", result.error)
            self.assertTrue(payload.exists())

    def test_clean_refuses_forged_cache_category_path(self):
        with TemporaryDirectory() as temp:
            home = Path(temp)
            cache = home / "Documents/NotHomebrew"
            cache.mkdir(parents=True)
            payload = cache / "keep.txt"
            payload.write_text("safe")
            target = ScanTarget(
                category="brew-cache",
                label="Homebrew cache",
                path=cache,
                size_bytes=1,
                modified_at=None,
                cleanable=True,
                delete_mode="contents",
                safety_root=home,
            )

            result = clean_target(target)

            self.assertFalse(result.removed)
            self.assertIn("known cleanable cache location", result.error)
            self.assertTrue(payload.exists())

    def test_find_node_modules_skips_nested_dependencies(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            nested = root / "app/node_modules/pkg/node_modules"
            nested.mkdir(parents=True)

            found = list(find_node_modules(root))

            self.assertEqual(found, [root / "app/node_modules"])

    def test_node_modules_older_than_filter(self):
        with TemporaryDirectory() as temp:
            home = Path(temp) / "home"
            root = Path(temp) / "work"
            home.mkdir()
            old_nm = root / "old-app/node_modules"
            new_nm = root / "new-app/node_modules"
            old_nm.mkdir(parents=True)
            new_nm.mkdir(parents=True)
            (old_nm / "pkg-cache.bin").write_bytes(b"x" * LARGE_PAYLOAD_BYTES)
            (new_nm / "pkg-cache.bin").write_bytes(b"x" * LARGE_PAYLOAD_BYTES)

            now = datetime(2026, 6, 6, tzinfo=timezone.utc)
            old_time = (now - timedelta(days=90)).timestamp()
            new_time = (now - timedelta(days=5)).timestamp()
            os.utime(old_nm, (old_time, old_time))
            os.utime(new_nm, (new_time, new_time))

            items = scan(
                home=home,
                cwd=root,
                search_roots=[root],
                include_node_modules=True,
                node_modules_older_than=timedelta(days=60),
                now=now,
            )

            paths = {item.path for item in items if item.category == "node-modules"}
            self.assertEqual(paths, {old_nm})

    def test_node_modules_search_skips_home_root(self):
        with TemporaryDirectory() as temp:
            home = Path(temp)
            node_modules = home / "app/node_modules"
            node_modules.mkdir(parents=True)

            items = scan(
                home=home,
                cwd=home,
                search_roots=[home],
                include_node_modules=True,
            )

            self.assertEqual([item for item in items if item.category == "node-modules"], [])


if __name__ == "__main__":
    unittest.main()
