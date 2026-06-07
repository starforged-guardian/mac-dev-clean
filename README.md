# mac-dev-clean

[![CI](https://github.com/starforged-guardian/mac-dev-clean/actions/workflows/ci.yml/badge.svg)](https://github.com/starforged-guardian/mac-dev-clean/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Python 3.9+](https://img.shields.io/badge/python-3.9%2B-blue.svg)](pyproject.toml)
[![macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](README.md)
[![Install with pipx](https://img.shields.io/badge/install-pipx-6650a4.svg)](#install)

Safe, dry-run-first cleanup tools for macOS developer disk bloat.

`mac-dev-clean` scans common developer cache locations and reports disk usage without deleting anything by default. `xcode-sim-prune` focuses on Xcode simulator storage using `xcrun simctl` instead of deleting simulator internals directly.

## Why This Matters

Xcode, simulators, Homebrew, Docker Desktop, npm, pnpm, Gradle, browser caches, and project `node_modules` directories can quietly consume huge amounts of disk space. That hurts more now that Mac storage upgrades are expensive and many developers are still working on 256GB MacBooks or base-model machines with little room for simulator runtimes, build artifacts, and dependency caches. Developers often recover that space with risky shell snippets copied from posts, chats, or old dotfiles. This project turns those cleanups into tested, explicit commands with dry-run output, JSON reports, safety-root checks, CI, and MIT-licensed source code.

## Install

Recommended GitHub install with `pipx`:

```sh
pipx install git+https://github.com/starforged-guardian/mac-dev-clean.git
```

Install with `pip`:

```sh
python3 -m pip install git+https://github.com/starforged-guardian/mac-dev-clean.git
```

Install from a local checkout:

```sh
python3 -m pip install -e .
```

On macOS, `pip` may install the commands into your user Python scripts directory. If `mac-dev-clean` or `xcode-sim-prune` is not found after installation, add that directory to your shell path:

```sh
export PATH="$HOME/Library/Python/3.9/bin:$PATH"
```

To make that permanent for zsh:

```sh
printf '\nexport PATH="$HOME/Library/Python/3.9/bin:$PATH"\n' >> ~/.zprofile
```

Or run without installing:

```sh
PYTHONPATH=src python3 -m mac_dev_clean scan
```

## Quick Demo

Find developer cache usage:

```sh
mac-dev-clean scan
mac-dev-clean report --json
```

Scan cleanable cache locations and confirm deletion interactively:

```sh
mac-dev-clean
```

Preview cleanup without deleting files:

```sh
mac-dev-clean clean --xcode-derived-data --dry-run
mac-dev-clean clean --xcode-device-support --dry-run
mac-dev-clean clean --package-caches --browser-caches --dry-run
mac-dev-clean clean --node-modules --older-than 60d --search-root ~/Code --dry-run
```

Inspect and prune simulator storage:

```sh
xcode-sim-prune
xcode-sim-prune list
xcode-sim-prune erase-unused --dry-run
xcode-sim-prune delete-runtimes --older-than 180d --dry-run
```

## Commands

Scan common locations and print a table:

```sh
mac-dev-clean scan
```

Print the same report as JSON:

```sh
mac-dev-clean report --json
```

Scan cleanable cache locations and delete them after a `y/N` prompt:

```sh
mac-dev-clean
```

Include old `node_modules` directories in the interactive scan:

```sh
mac-dev-clean interactive --include-node-modules --older-than 60d --search-root ~/Code
```

Preview cleaning Xcode build artifacts:

```sh
mac-dev-clean clean --xcode-derived-data --dry-run
```

Clean Xcode DerivedData and module cache:

```sh
mac-dev-clean clean --xcode-derived-data
```

Clean Xcode documentation cache:

```sh
mac-dev-clean clean --xcode-documentation-cache
```

Clean Xcode DeviceSupport files:

```sh
mac-dev-clean clean --xcode-device-support --dry-run
mac-dev-clean clean --xcode-device-support
```

Clean simulator caches and logs:

```sh
mac-dev-clean clean --simulator-caches
```

Clean Homebrew cache:

```sh
mac-dev-clean clean --brew-cache
```

Clean old `node_modules` directories:

```sh
mac-dev-clean clean --node-modules --older-than 60d --dry-run
mac-dev-clean clean --node-modules --older-than 60d
```

Clean dependency and tool caches:

```sh
mac-dev-clean clean --package-caches --dry-run
mac-dev-clean clean --package-caches
```

Clean supported browser caches:

```sh
mac-dev-clean clean --browser-caches --dry-run
mac-dev-clean clean --browser-caches
```

Search specific roots for `node_modules`:

```sh
mac-dev-clean scan --search-root ~/Code --search-root ~/Projects
mac-dev-clean clean --node-modules --older-than 90d --search-root ~/Code
```

## What It Scans

Cleanable locations:

- Xcode DerivedData: `~/Library/Developer/Xcode/DerivedData`
- Xcode module cache: `~/Library/Developer/Xcode/ModuleCache.noindex`
- Xcode documentation cache: `~/Library/Developer/Xcode/DocumentationCache`
- Xcode DeviceSupport: `~/Library/Developer/Xcode/{iOS,tvOS,watchOS,visionOS} DeviceSupport`
- CoreSimulator caches: `~/Library/Developer/CoreSimulator/Caches`
- CoreSimulator logs: `~/Library/Logs/CoreSimulator`
- Simulator device caches: `~/Library/Developer/CoreSimulator/Devices/*/data/Library/Caches`
- Homebrew cache: `~/Library/Caches/Homebrew`
- npm cache and logs: `~/.npm/_cacache`, `~/.npm/_logs`
- pnpm store and cache: `~/Library/pnpm/store`, `~/Library/Caches/pnpm`
- Node tooling caches: `~/Library/Caches/node-gyp`, `~/Library/Caches/typescript`, `~/Library/Caches/bun`
- Python caches: `~/Library/Caches/pip`, `~/.cache/pip`, `~/Library/Caches/pypoetry`, `~/.cache/pypoetry`
- SwiftPM cache: `~/Library/Caches/org.swift.swiftpm`
- Go caches: `~/Library/Caches/go-build`, `~/go/pkg/mod`
- Rust caches: `~/.cargo/registry`, `~/.cargo/git`
- Gradle caches: `~/.gradle/caches`, `~/.gradle/daemon`, `~/.gradle/wrapper/dists`
- Browser caches: `~/Library/Caches/Google`, `~/Library/Caches/BraveSoftware`, `~/Library/Caches/Firefox`, `~/Library/Caches/com.apple.Safari`
- Discovered project `node_modules` directories

Report-only locations:

- Xcode Archives: `~/Library/Developer/Xcode/Archives`
- Docker Desktop logs: `~/Library/Containers/com.docker.docker/Data/log`
- Docker Desktop VM data: `~/Library/Containers/com.docker.docker/Data/vms`
- Codex runtime cache: `~/.cache/codex-runtimes`

Docker VM data is intentionally report-only because deleting it directly can remove images, containers, and volumes. Use Docker's own prune commands for Docker cleanup.

## Safety Model

- `scan` and `report` never delete files.
- Running `mac-dev-clean` without arguments scans cleanable cache locations and prompts before deleting anything.
- `interactive --include-node-modules` requires `--older-than`, such as `60d`.
- `clean` fails unless you pass at least one explicit category flag.
- `--node-modules` requires `--older-than`, such as `60d`.
- Fixed cache directories use contents-only cleanup, preserving the parent directory.
- `node_modules` cleanup removes the selected `node_modules` directory tree.
- Xcode DeviceSupport cleanup removes cached support files that Xcode can recreate when needed.
- Xcode Archives, Docker data, and active-session runtime caches are report-only.
- Cleanup targets must match known cache path shapes and stay inside their scan safety root.
- Symlink targets are refused.
- Cleanable scan targets under 1 MiB are skipped to avoid recommending no-op cleanup.
- Use `--dry-run` before deleting to see the selected paths.

Supported age values are `s`, `m`, `h`, `d`, and `w`, for example `30d`, `12h`, or `2w`.

## xcode-sim-prune

This repository also includes `xcode-sim-prune`, a focused CLI for Xcode simulator storage. It uses `xcrun simctl` for simulator operations instead of deleting simulator internals directly.

Run an automatic scan and confirm safe simulator device deletion interactively:

```sh
xcode-sim-prune
```

By default, `xcode-sim-prune` prompts before deleting shutdown simulator devices that are unavailable to the current Xcode or have never been booted.

List simulator devices and runtime images:

```sh
xcode-sim-prune list
xcode-sim-prune list --json
```

Preview and delete unavailable devices:

```sh
xcode-sim-prune delete-unavailable --dry-run
xcode-sim-prune delete-unavailable
```

Preview and delete specific shutdown simulator devices by exact name or UDID:

```sh
xcode-sim-prune delete-devices --name "iPhone 17" --dry-run
xcode-sim-prune delete-devices --name "iPhone 17"
xcode-sim-prune delete-devices --udid BB56347C-413D-42CF-AA83-98F77434BE4A --dry-run
```

Preview a broader pass that keeps named devices:

```sh
xcode-sim-prune delete-devices --all-shutdown --keep-name "iPhone 17 Pro" --dry-run
```

Preview and delete runtime images not used within an age threshold:

```sh
xcode-sim-prune delete-runtimes --older-than 180d --dry-run
xcode-sim-prune delete-runtimes --older-than 180d
```

Preview and erase unused simulator device data:

```sh
xcode-sim-prune erase-unused --dry-run
xcode-sim-prune erase-unused
```

By default, `erase-unused` only targets shutdown devices that have never been booted. To also include stale shutdown devices, pass an age filter:

```sh
xcode-sim-prune erase-unused --older-than 60d --dry-run
```

Safety notes:

- `list` never changes anything.
- Running `xcode-sim-prune` without arguments scans safe simulator device deletion candidates and prompts before deleting anything.
- `delete-unavailable` delegates to `xcrun simctl delete unavailable`.
- `delete-devices` only deletes shutdown devices with safe UDIDs; names are exact matches, so `iPhone 17` does not match `iPhone 17 Pro`.
- `delete-runtimes` requires `--older-than` and delegates to `xcrun simctl runtime delete --notUsedSinceDays`.
- `erase-unused` never erases booted devices.
- Malformed simulator device IDs are ignored before calling `simctl`.
- All destructive commands support `--dry-run` and `--json`.

## Development

Run tests:

```sh
PYTHONPATH=src python3 -m unittest discover -s tests
```

Run smoke checks:

```sh
PYTHONPATH=src python3 -m mac_dev_clean report --json --no-node-modules
PYTHONPATH=src python3 -m mac_dev_clean.xcode_sim_prune list --json
```

## Contributing

Contributions are welcome. Please keep changes aligned with the safety model: scans must be read-only, deletion must be explicit, and new cleanup behavior should include tests.

## License

`mac-dev-clean` is open source software released under the MIT License. See [LICENSE](LICENSE).
