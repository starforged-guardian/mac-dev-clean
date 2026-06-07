import contextlib
import io
import json
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from mac_dev_clean.sim_prune import ActionReport, Device, Inventory
from mac_dev_clean.xcode_sim_prune import main


class XcodeSimPruneCliTests(unittest.TestCase):
    def test_default_command_reports_no_candidates(self):
        stdout = io.StringIO()

        with contextlib.ExitStack() as stack:
            stack.enter_context(
                patch(
                    "mac_dev_clean.xcode_sim_prune.load_inventory",
                    return_value=Inventory(devices=[], runtimes=[]),
                )
            )
            delete_devices = stack.enter_context(patch("mac_dev_clean.xcode_sim_prune.delete_devices"))
            stack.enter_context(contextlib.redirect_stdout(stdout))
            code = main([])

        self.assertEqual(code, 0)
        delete_devices.assert_not_called()
        self.assertIn("No safe simulator cleanup candidates found.", stdout.getvalue())

    def test_default_command_cancel_does_not_delete(self):
        device = Device(
            runtime_identifier="com.apple.CoreSimulator.SimRuntime.iOS-26-5",
            name="iPhone Never",
            udid="BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            state="Shutdown",
            is_available=True,
            last_booted_at=None,
            data_size_bytes=100,
            log_size_bytes=0,
        )
        preview = ActionReport(
            action="delete-devices",
            dry_run=True,
            command=["/usr/bin/xcrun", "simctl", "delete", device.udid],
            targets=[device.to_dict()],
        )
        stdout = io.StringIO()

        with contextlib.ExitStack() as stack:
            stack.enter_context(
                patch(
                    "mac_dev_clean.xcode_sim_prune.load_inventory",
                    return_value=Inventory(devices=[device], runtimes=[]),
                )
            )
            delete_devices = stack.enter_context(
                patch("mac_dev_clean.xcode_sim_prune.delete_devices", return_value=preview)
            )
            stack.enter_context(patch("builtins.input", return_value="n"))
            stack.enter_context(contextlib.redirect_stdout(stdout))
            code = main([])

        self.assertEqual(code, 0)
        delete_devices.assert_called_once()
        self.assertTrue(delete_devices.call_args.kwargs["dry_run"])
        self.assertIn("Canceled. Nothing deleted.", stdout.getvalue())

    def test_default_command_confirm_deletes_candidates(self):
        device = Device(
            runtime_identifier="com.apple.CoreSimulator.SimRuntime.iOS-26-5",
            name="iPhone Missing Runtime",
            udid="DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD",
            state="Shutdown",
            is_available=False,
            last_booted_at=datetime(2026, 6, 1, tzinfo=timezone.utc),
            data_size_bytes=100,
            log_size_bytes=0,
        )
        preview = ActionReport(
            action="delete-devices",
            dry_run=True,
            command=["/usr/bin/xcrun", "simctl", "delete", device.udid],
            targets=[device.to_dict()],
        )
        result = ActionReport(
            action="delete-devices",
            dry_run=False,
            command=["/usr/bin/xcrun", "simctl", "delete", device.udid],
            targets=[device.to_dict()],
        )
        stdout = io.StringIO()

        with contextlib.ExitStack() as stack:
            stack.enter_context(
                patch(
                    "mac_dev_clean.xcode_sim_prune.load_inventory",
                    return_value=Inventory(devices=[device], runtimes=[]),
                )
            )
            delete_devices = stack.enter_context(
                patch("mac_dev_clean.xcode_sim_prune.delete_devices", side_effect=[preview, result])
            )
            stack.enter_context(patch("builtins.input", return_value="y"))
            stack.enter_context(contextlib.redirect_stdout(stdout))
            code = main(["interactive"])

        self.assertEqual(code, 0)
        self.assertEqual(len(delete_devices.call_args_list), 2)
        self.assertTrue(delete_devices.call_args_list[0].kwargs["dry_run"])
        self.assertFalse(delete_devices.call_args_list[1].kwargs["dry_run"])
        self.assertEqual(delete_devices.call_args_list[1].kwargs["udids"], [device.udid])

    def test_list_json_outputs_valid_inventory_json(self):
        stdout = io.StringIO()
        with patch("mac_dev_clean.xcode_sim_prune.load_inventory", return_value=Inventory(devices=[], runtimes=[])):
            with contextlib.redirect_stdout(stdout):
                code = main(["list", "--json"])

        self.assertEqual(code, 0)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["device_count"], 0)
        self.assertEqual(payload["runtime_count"], 0)

    def test_delete_runtimes_requires_older_than(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr), self.assertRaises(SystemExit) as raised:
            main(["delete-runtimes"])

        self.assertEqual(raised.exception.code, 2)
        self.assertIn("--older-than", stderr.getvalue())

    def test_delete_devices_requires_selector(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr), self.assertRaises(SystemExit) as raised:
            main(["delete-devices", "--dry-run"])

        self.assertEqual(raised.exception.code, 2)
        self.assertIn("delete-devices requires --name, --udid, or --all-shutdown", stderr.getvalue())

    def test_delete_devices_passes_name_filters(self):
        stdout = io.StringIO()
        report = ActionReport(
            action="delete-devices",
            dry_run=True,
            command=["/usr/bin/xcrun", "simctl", "delete"],
            targets=[],
        )

        with contextlib.ExitStack() as stack:
            stack.enter_context(
                patch("mac_dev_clean.xcode_sim_prune.load_inventory", return_value=Inventory(devices=[], runtimes=[]))
            )
            delete_devices = stack.enter_context(
                patch("mac_dev_clean.xcode_sim_prune.delete_devices", return_value=report)
            )
            stack.enter_context(contextlib.redirect_stdout(stdout))
            code = main(["delete-devices", "--name", "iPhone 17", "--dry-run"])

        self.assertEqual(code, 0)
        delete_devices.assert_called_once()
        self.assertEqual(delete_devices.call_args.kwargs["names"], ["iPhone 17"])
        self.assertTrue(delete_devices.call_args.kwargs["dry_run"])


if __name__ == "__main__":
    unittest.main()
