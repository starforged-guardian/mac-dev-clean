# Security Policy

`mac-dev-clean` and `xcode-sim-prune` are intentionally conservative because they operate near local developer data.

## Supported Versions

Security fixes target the current `main` branch until the project starts publishing versioned releases.

## Reporting a Vulnerability

If this repository has GitHub Security Advisories enabled, please report vulnerabilities through a private security advisory. Otherwise, open an issue with a minimal description and avoid including sensitive local paths, credentials, or private project names.

## Security Model

- Scanning and reporting commands must be read-only.
- Destructive commands must require explicit user-selected actions.
- Dry-run output should show the same target selection used by the destructive path.
- Cleanup targets must match known cache path shapes and stay inside their safety root.
- Symlink targets are refused.
- Directory removal requires Python's symlink-safe `shutil.rmtree` implementation.
- `xcode-sim-prune` uses `/usr/bin/xcrun` and does not invoke a shell.

