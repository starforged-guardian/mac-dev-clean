import contextlib
import io
import json
import unittest
from unittest.mock import patch

from mac_dev_clean.cli import main


class CliTests(unittest.TestCase):
    def test_clean_requires_explicit_flag(self):
        stderr = io.StringIO()
        with self.assertRaises(SystemExit) as raised, contextlib.redirect_stderr(stderr):
            main(["clean"])

        self.assertEqual(raised.exception.code, 2)
        self.assertIn("clean requires at least one explicit category flag", stderr.getvalue())

    def test_node_modules_clean_requires_age_filter(self):
        stderr = io.StringIO()
        with self.assertRaises(SystemExit) as raised, contextlib.redirect_stderr(stderr):
            main(["clean", "--node-modules", "--dry-run"])

        self.assertEqual(raised.exception.code, 2)
        self.assertIn("--node-modules requires --older-than", stderr.getvalue())

    def test_report_json_outputs_valid_json(self):
        stdout = io.StringIO()
        with patch("mac_dev_clean.cli.scan", return_value=[]), contextlib.redirect_stdout(stdout):
            code = main(["report", "--json", "--no-node-modules"])

        self.assertEqual(code, 0)
        payload = json.loads(stdout.getvalue())
        self.assertIn("items", payload)
        self.assertIn("total_bytes", payload)


if __name__ == "__main__":
    unittest.main()
