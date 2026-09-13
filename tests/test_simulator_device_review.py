"""Safety checks for the GUI's explicit per-device deletion endpoint."""
import errno
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from mac_dev_clean import xcode_sim_prune
from mac_dev_clean.cleaner import _remove_contents, _remove_path
from mac_dev_clean.sim_prune import delete_device, load_devices

UDID = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
OTHER = "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"


def inventory(state="Shutdown"):
    return json.dumps({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
        {"name": "iPhone", "udid": UDID, "state": state, "isAvailable": True,
         "dataPathSize": 2_000_000_000},
        {"name": "iPhone", "udid": OTHER, "state": "Shutdown", "isAvailable": True},
    ]}})


class SimulatorReviewTests(unittest.TestCase):
    def test_inventory_does_not_depend_on_runtime_image_service(self):
        calls = []
        def runner(args):
            calls.append(args)
            return inventory()
        self.assertEqual(len(load_devices(runner).devices), 2)
        self.assertEqual(calls, [["list", "--json", "devices"]])

    def test_deletes_only_requested_id_after_live_query(self):
        calls = []
        def runner(args):
            calls.append(args)
            return inventory() if args[0] == "list" else ""
        result = delete_device(UDID.lower(), runner)
        self.assertEqual(calls, [["list", "--json", "devices"], ["delete", UDID]])
        self.assertEqual([item["udid"] for item in result.targets], [UDID])
        self.assertFalse(result.dry_run)

    def test_active_and_unknown_states_are_rejected_without_deletion(self):
        for state in ["Booted", "Booting", "Shutting Down", "Creating", ""]:
            with self.subTest(state=state):
                calls = []
                def runner(args):
                    calls.append(args)
                    return inventory(state)
                with self.assertRaisesRegex(ValueError, "only shutdown"):
                    delete_device(UDID, runner)
                self.assertEqual(len(calls), 1)

    def test_invalid_or_missing_ids_never_delete(self):
        for udid in ["all", "unavailable", "--all", "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"]:
            calls = []
            def runner(args):
                calls.append(args)
                return inventory()
            with self.assertRaises(ValueError):
                delete_device(udid, runner)
            self.assertFalse(any(args[0] == "delete" for args in calls))

    def test_dry_run_lists_one_target_and_never_mutates(self):
        calls = []
        def runner(args):
            calls.append(args)
            return inventory()
        result = delete_device(UDID, runner, dry_run=True)
        self.assertTrue(result.dry_run)
        self.assertEqual(len(result.targets), 1)
        self.assertEqual(len(calls), 1)

    def test_cli_routes_exact_id_and_dry_run(self):
        report = delete_device(UDID, lambda _: inventory(), dry_run=True)
        with patch.object(xcode_sim_prune, "delete_device", return_value=report) as delete, patch("builtins.print"):
            self.assertEqual(xcode_sim_prune.main(["delete-device", "--udid", UDID, "--dry-run", "--json"]), 0)
        delete.assert_called_once_with(UDID, dry_run=True)

    def test_busy_cache_does_not_prevent_cleaning_other_children(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            busy, removable = root / "busy", root / "removable"
            busy.mkdir()
            removable.write_text("cache")
            def remove(path):
                if path == busy:
                    raise OSError(errno.ENOTEMPTY, "Directory not empty")
                _remove_path(path)
            with patch("mac_dev_clean.cleaner._remove_path", side_effect=remove):
                with self.assertRaisesRegex(OSError, "Quit the app"):
                    _remove_contents(root)
            self.assertFalse(removable.exists())
            self.assertTrue(busy.exists())

    def test_missing_cache_entry_is_tolerated(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "vanishing").touch()
            with patch("mac_dev_clean.cleaner._remove_path", side_effect=FileNotFoundError):
                _remove_contents(root)

    def test_permission_errors_are_not_silently_reported_as_success(self):
        with patch("mac_dev_clean.cleaner.os.lstat", side_effect=PermissionError("denied")):
            with self.assertRaises(PermissionError):
                _remove_path(Path("/unused"))

    def test_busy_nested_cache_does_not_abandon_other_profile_caches(self):
        with TemporaryDirectory() as temp:
            root = Path(temp) / "Chrome"
            busy = root / "Default" / "Cache_Data"
            other = root / "Profile 2" / "Cache_Data"
            busy.mkdir(parents=True)
            other.mkdir(parents=True)
            (busy / "held").write_text("cache")
            (other / "removable").write_text("cache")
            import os
            original_unlink = os.unlink
            def unlink(path, *args, **kwargs):
                if path == "held":
                    raise OSError(errno.EBUSY, "Resource busy")
                return original_unlink(path, *args, **kwargs)
            with patch("os.unlink", side_effect=unlink):
                with self.assertRaises(OSError):
                    _remove_path(root)
            self.assertTrue((busy / "held").exists())
            self.assertFalse(other.exists())
