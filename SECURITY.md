# Security Policy

`mac-dev-clean` and `xcode-sim-prune` are intentionally conservative because they operate near local developer data.

## Supported Versions

Security fixes target the current `main` branch until the project starts publishing versioned releases.

## Reporting a Vulnerability

Use a private GitHub Security Advisory when available. Include the affected
command or app version, expected safety boundary, and minimal reproduction.
Redact usernames, local paths, project names, device identifiers, Apple Account
information, credentials, and file contents.

If private advisories are unavailable, open an issue containing only a minimal
description and ask the maintainers for a private follow-up channel. Do not
publish an active deletion-bypass exploit or credentials in a public issue.

## Security Model

- Scanning and reporting commands must be read-only.
- Destructive commands must require explicit user-selected actions.
- Dry-run output should show the same target selection used by the destructive path.
- Cleanup targets must match known cache path shapes and stay inside their safety root.
- Symlink targets are refused.
- Directory removal requires Python's symlink-safe `shutil.rmtree` implementation.
- `xcode-sim-prune` uses `/usr/bin/xcrun` and does not invoke a shell.

## Native App Boundaries

- Opening the app performs a read-only scan; cleanup requires selected
  cleanable groups and a native confirmation.
- Review-only paths are kept out of cleanup command construction.
- The automatic scan excludes project discovery and protected user folders.
- The app invokes a fixed Python executable and module argument array directly,
  without shell interpolation.
- The app clears inherited `PYTHON*` settings, uses only its bundled Python
  module path, and disables user-site packages.
- The app is hardened-runtime enabled for Developer ID distribution. It is not
  App Sandbox-enabled because it must inspect developer caches throughout the
  user's Library.
- The iCloud action opens Finder only. No cloud move or deletion is automated.

## Build and Release Security

- GitHub Actions has read-only repository permission and performs unsigned
  builds; signing credentials are never required by CI.
- Developer ID private keys stay in Keychain. Notarization credentials are
  stored in a named `notarytool` Keychain profile.
- Certificate exports, private keys, provisioning profiles, Xcode user state,
  local archives, and notarization logs are ignored by Git.
- Release artifacts should be verified with `codesign`, `spctl`, notarization
  ticket validation, and the published SHA-256 checksum.

See [docs/OPEN_SOURCE_AUDIT.md](docs/OPEN_SOURCE_AUDIT.md) for the public-push
checklist and [PRIVACY.md](PRIVACY.md) for local data handling.
