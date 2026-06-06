## Summary

Describe the change and why it belongs in `mac-dev-clean`.

## Safety Checklist

- [ ] Scans/reports remain read-only.
- [ ] Destructive behavior requires an explicit user flag or action.
- [ ] Dry-run output matches the targets used by the destructive path.
- [ ] Cleanup targets are constrained to known cache path shapes and safety roots.
- [ ] Symlink or malformed-target refusal behavior is preserved.

## Tests

Paste the commands you ran:

```sh
PYTHONPATH=src python3 -m unittest discover -s tests
PYTHONPYCACHEPREFIX=/private/tmp/mac-dev-clean-pycache python3 -m compileall -q src tests
```

## macOS / Xcode Context

Include macOS and Xcode versions if this touches Xcode, CoreSimulator, or `xcode-sim-prune`.

