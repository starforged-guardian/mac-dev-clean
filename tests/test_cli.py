import contextlib
import io
import json
import unittest
from pathlib import Path
from unittest.mock import patch

from mac_dev_clean.cli import main
from mac_dev_clean.model import CleanResult, ScanTarget


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

    def test_default_command_cancel_does_not_clean(self):
        target = ScanTarget(
            category="brew-cache",
            label="Homebrew cache",
            path=Path("/tmp/home/Library/Caches/Homebrew"),
            size_bytes=1,
            modified_at=None,
            cleanable=True,
            delete_mode="contents",
            safety_root=Path("/tmp/home"),
        )
        stdout = io.StringIO()

        with contextlib.ExitStack() as stack:
            stack.enter_context(patch("mac_dev_clean.cli.scan", return_value=[target]))
            clean_targets = stack.enter_context(patch("mac_dev_clean.cli.clean_targets"))
            stack.enter_context(patch("builtins.input", return_value="n"))
            stack.enter_context(contextlib.redirect_stdout(stdout))
            code = main([])

        self.assertEqual(code, 0)
        clean_targets.assert_not_called()
        self.assertIn("Canceled. Nothing deleted.", stdout.getvalue())

    def test_interactive_yes_cleans_cleanable_targets(self):
        cleanable = ScanTarget(
            category="brew-cache",
            label="Homebrew cache",
            path=Path("/tmp/home/Library/Caches/Homebrew"),
            size_bytes=1,
            modified_at=None,
            cleanable=True,
            delete_mode="contents",
            safety_root=Path("/tmp/home"),
        )
        report_only = ScanTarget(
            category="docker",
            label="Docker Desktop VM data",
            path=Path("/tmp/home/Library/Containers/com.docker.docker/Data/vms"),
            size_bytes=1,
            modified_at=None,
            cleanable=False,
            delete_mode="none",
            safety_root=Path("/tmp/home"),
        )
        result = CleanResult(
            category="brew-cache",
            label="Homebrew cache",
            path=cleanable.path,
            size_bytes=1,
            dry_run=False,
            removed=True,
        )
        stdout = io.StringIO()

        with contextlib.ExitStack() as stack:
            stack.enter_context(
                patch("mac_dev_clean.cli.scan", return_value=[cleanable, report_only])
            )
            clean_targets = stack.enter_context(
                patch("mac_dev_clean.cli.clean_targets", return_value=[result])
            )
            stack.enter_context(patch("builtins.input", return_value="y"))
            stack.enter_context(contextlib.redirect_stdout(stdout))
            code = main(["interactive"])

        self.assertEqual(code, 0)
        clean_targets.assert_called_once_with([cleanable])
        self.assertIn("removed", stdout.getvalue())

    def test_interactive_include_node_modules_requires_age_filter(self):
        stderr = io.StringIO()
        with self.assertRaises(SystemExit) as raised, contextlib.redirect_stderr(stderr):
            main(["interactive", "--include-node-modules"])

        self.assertEqual(raised.exception.code, 2)
        self.assertIn("interactive --include-node-modules requires --older-than", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
