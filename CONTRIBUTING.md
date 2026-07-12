# Contributing

Thanks for helping improve `mac-dev-clean`.

## Development

Run the test suite from the repository root:

```sh
PYTHONPATH=src python3 -m unittest discover -s tests
```

Run a bytecode compile check:

```sh
PYTHONPYCACHEPREFIX=/private/tmp/mac-dev-clean-pycache python3 -m compileall -q src tests
```

Run the native UI tests and unsigned Xcode build:

```sh
swift test --package-path macos
xcodebuild \
  -project macos/MacDevClean.xcodeproj \
  -scheme MacDevCleanApp \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

`macos/project.yml` is the source of truth for project structure and build
settings. If it changes, regenerate `macos/MacDevClean.xcodeproj` with XcodeGen
and include the generated project diff. See
[docs/NATIVE_MACOS_APP.md](docs/NATIVE_MACOS_APP.md).

## Publishing a Release

Add user-facing changes under `## Unreleased` in `CHANGELOG.md`, commit them to
`main`, and make sure the working tree is clean. Then preview the next patch
release:

```sh
./scripts/release.py --dry-run
```

Publish it with one confirmed command:

```sh
./scripts/release.py
```

Pass `minor`, `major`, or an explicit version when needed:

```sh
./scripts/release.py minor
./scripts/release.py 1.0.0
```

The helper requires authenticated `gh` and an up-to-date `main` branch. It
updates the Python package and native app version declarations, dates the
changelog section, runs the Python and Swift tests plus an unsigned native app
build, commits and pushes the release, creates the GitHub tag/release, and then
fetches the new tag locally. Use `--yes` only when non-interactive publishing is
intentional.

## Safety Rules

This project works near developer cache directories, so changes should keep the safety model boring and explicit:

- Scans and reports must never delete data.
- Destructive commands must require an explicit category or action.
- Prefer official tools such as `xcrun simctl` over deleting tool internals directly.
- Add or update tests for every new deletion path.
- Keep cleanup targets constrained to known cache path shapes and safety roots.
- Keep dry-run output accurate enough that a user can see what would be affected.

## Public Repository Hygiene

- Never commit credentials, `.env` files, private keys, certificates,
  provisioning profiles, notarization logs, or Apple Account information.
- Do not commit `.swiftpm`, `xcuserdata`, `*.xcuserstate`, DerivedData, archives,
  result bundles, dSYMs, or other machine-specific Xcode output.
- Use generic fixture paths such as `/Users/test/...`; redact real usernames,
  project names, and device identifiers from tests, screenshots, and issues.
- Run the checklist in
  [docs/OPEN_SOURCE_AUDIT.md](docs/OPEN_SOURCE_AUDIT.md) before publishing a
  release or accepting a change that touches signing, CI, or build scripts.
- Run `./scripts/audit_public_repo.sh` before pushing; it also scans the working
  tree and history when Gitleaks is installed.
- Confirm every new bundled image, font, or data file is licensed for public
  redistribution. Forks and modified builds must remove or replace Raven Vector
  brand assets before distribution as described in [BRANDING.md](BRANDING.md).

## License

By contributing, you agree that your code and documentation contributions are
licensed under the MIT License. Do not contribute third-party or brand artwork
unless you have authority to provide it under the repository's stated terms.
