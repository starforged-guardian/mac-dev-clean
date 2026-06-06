from datetime import datetime, timedelta, timezone
import json
import unittest

from mac_dev_clean.sim_prune import (
    Inventory,
    RuntimeImage,
    age_to_days,
    delete_runtimes,
    delete_unavailable,
    erase_unused,
    parse_devices_json,
    parse_runtime_images_json,
    select_unused_devices,
)


DEVICES_JSON = json.dumps(
    {
        "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
                {
                    "name": "iPhone Booted",
                    "udid": "BOOTED",
                    "state": "Booted",
                    "isAvailable": True,
                    "lastBootedAt": "2026-06-06T16:57:39Z",
                    "dataPathSize": 100,
                    "logPathSize": 20,
                },
                {
                    "name": "iPhone Never",
                    "udid": "NEVER",
                    "state": "Shutdown",
                    "isAvailable": True,
                    "dataPathSize": 50,
                },
                {
                    "name": "iPhone Old",
                    "udid": "OLD",
                    "state": "Shutdown",
                    "isAvailable": True,
                    "lastBootedAt": "2025-01-01T00:00:00Z",
                    "dataPathSize": 25,
                },
                {
                    "name": "iPhone Missing Runtime",
                    "udid": "UNAVAILABLE",
                    "state": "Shutdown",
                    "isAvailable": False,
                    "dataPathSize": 10,
                },
            ]
        }
    }
)


RUNTIMES_JSON = json.dumps(
    {
        "RUNTIME-IMAGE-OLD": {
            "identifier": "RUNTIME-IMAGE-OLD",
            "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-17-0",
            "runtimeBundlePath": "/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 17.0.simruntime",
            "version": "17.0",
            "build": "21A",
            "platformIdentifier": "com.apple.platform.iphonesimulator",
            "state": "Ready",
            "deletable": True,
            "lastUsedAt": "2025-01-01T00:00:00Z",
            "sizeBytes": 1000,
        },
        "RUNTIME-IMAGE-NEW": {
            "identifier": "RUNTIME-IMAGE-NEW",
            "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
            "runtimeBundlePath": "/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 26.5.simruntime",
            "version": "26.5",
            "build": "23F",
            "platformIdentifier": "com.apple.platform.iphonesimulator",
            "state": "Ready",
            "deletable": True,
            "lastUsedAt": "2026-06-01T00:00:00Z",
            "sizeBytes": 2000,
        },
    }
)


class SimPruneTests(unittest.TestCase):
    def test_parse_devices_json_flattens_runtime_groups(self):
        devices = parse_devices_json(DEVICES_JSON)

        self.assertEqual(len(devices), 4)
        self.assertEqual(devices[0].udid, "BOOTED")
        self.assertEqual(devices[0].total_size_bytes, 120)

    def test_default_unused_devices_only_selects_never_booted_shutdown_devices(self):
        devices = parse_devices_json(DEVICES_JSON)

        selected = select_unused_devices(devices)

        self.assertEqual([device.udid for device in selected], ["NEVER"])

    def test_older_than_unused_devices_includes_stale_shutdown_devices(self):
        devices = parse_devices_json(DEVICES_JSON)
        now = datetime(2026, 6, 6, tzinfo=timezone.utc)

        selected = select_unused_devices(devices, older_than=timedelta(days=180), now=now)

        self.assertEqual([device.udid for device in selected], ["NEVER", "OLD"])

    def test_delete_unavailable_dry_run_does_not_call_runner(self):
        inventory = Inventory(devices=parse_devices_json(DEVICES_JSON), runtimes=[])

        report = delete_unavailable(inventory, runner=lambda _args: self.fail("runner called"), dry_run=True)

        self.assertEqual(report.action, "delete-unavailable")
        self.assertEqual([target["udid"] for target in report.targets], ["UNAVAILABLE"])

    def test_delete_runtimes_uses_simctl_not_used_since_days(self):
        inventory = Inventory(devices=[], runtimes=parse_runtime_images_json(RUNTIMES_JSON))
        calls = []

        report = delete_runtimes(
            inventory,
            older_than_days=180,
            runner=lambda args: calls.append(list(args)) or "deleted",
            dry_run=True,
            now=datetime(2026, 6, 6, tzinfo=timezone.utc),
        )

        self.assertEqual(calls, [["runtime", "delete", "--notUsedSinceDays", "180", "--dry-run"]])
        self.assertEqual([target["identifier"] for target in report.targets], ["RUNTIME-IMAGE-OLD"])

    def test_delete_runtimes_skips_simctl_when_no_candidates(self):
        inventory = Inventory(devices=[], runtimes=parse_runtime_images_json(RUNTIMES_JSON))

        report = delete_runtimes(
            inventory,
            older_than_days=180,
            runner=lambda _args: self.fail("runner called"),
            dry_run=True,
            now=datetime(2026, 6, 6, tzinfo=timezone.utc) - timedelta(days=400),
        )

        self.assertEqual(report.targets, [])

    def test_erase_unused_calls_simctl_with_selected_udids(self):
        inventory = Inventory(devices=parse_devices_json(DEVICES_JSON), runtimes=[])
        calls = []

        report = erase_unused(
            inventory,
            runner=lambda args: calls.append(list(args)) or "erased",
            dry_run=False,
        )

        self.assertEqual(calls, [["erase", "NEVER"]])
        self.assertEqual([target["udid"] for target in report.targets], ["NEVER"])

    def test_age_to_days_rounds_up_partial_days(self):
        self.assertEqual(age_to_days(timedelta(hours=12)), 1)
        self.assertEqual(age_to_days(timedelta(days=2, minutes=1)), 3)


if __name__ == "__main__":
    unittest.main()
