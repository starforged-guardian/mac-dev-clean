import contextlib
import io
import json
import unittest
from unittest.mock import patch

from mac_dev_clean.sim_prune import Inventory
from mac_dev_clean.xcode_sim_prune import main


class XcodeSimPruneCliTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()

