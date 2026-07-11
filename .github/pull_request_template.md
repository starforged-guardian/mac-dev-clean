## Summary

Describe the change and why it belongs in `mac-dev-clean`.

## Safety Checklist

- [ ] Scans/reports remain read-only.
- [ ] Destructive behavior requires an explicit user flag or action.
- [ ] Dry-run output matches the targets used by the destructive path.
- [ ] Cleanup targets are constrained to known cache path shapes and safety roots.
- [ ] Symlink or malformed-target refusal behavior is preserved.
- [ ] Native UI review-only items cannot enter the cleanup request.
- [ ] No credentials, personal paths, Xcode user state, or signing material are included.
- [ ] New bundled resources have clear public redistribution rights.

## Tests

Paste the commands you ran:

```sh
PYTHONPATH=src python3 -m unittest discover -s tests
PYTHONPYCACHEPREFIX=/private/tmp/mac-dev-clean-pycache python3 -m compileall -q src tests
swift test --package-path macos
xcodebuild -project macos/MacDevClean.xcodeproj -scheme MacDevCleanApp -configuration Release -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## macOS / Xcode Context

Include macOS and Xcode versions if this touches Xcode, CoreSimulator, or `xcode-sim-prune`.

If `macos/project.yml` changed, confirm the committed Xcode project was
regenerated with XcodeGen.
