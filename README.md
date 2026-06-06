# mac-dev-clean

`mac-dev-clean` is a small macOS CLI that finds developer caches and shows how much disk space they are using. It never deletes anything during `scan` or `report`, and `clean` requires explicit category flags before it removes files.

## Why

Xcode, simulators, Homebrew, Docker Desktop, npm, Gradle, and project `node_modules` directories can quietly consume a lot of disk space. This tool gives you a quick report and safe cleanup commands for common cache locations.

## Install

From the repository root:

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

## Commands

Scan common locations and print a table:

```sh
mac-dev-clean scan
```

Print the same report as JSON:

```sh
mac-dev-clean report --json
```

Preview cleaning Xcode build artifacts:

```sh
mac-dev-clean clean --xcode-derived-data --dry-run
```

Clean Xcode DerivedData and module cache:

```sh
mac-dev-clean clean --xcode-derived-data
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

Search specific roots for `node_modules`:

```sh
mac-dev-clean scan --search-root ~/Code --search-root ~/Projects
mac-dev-clean clean --node-modules --older-than 90d --search-root ~/Code
```

## What It Scans

Cleanable locations:

- Xcode DerivedData: `~/Library/Developer/Xcode/DerivedData`
- Xcode module cache: `~/Library/Developer/Xcode/ModuleCache.noindex`
- CoreSimulator caches: `~/Library/Developer/CoreSimulator/Caches`
- CoreSimulator logs: `~/Library/Logs/CoreSimulator`
- Simulator device caches: `~/Library/Developer/CoreSimulator/Devices/*/data/Library/Caches`
- Homebrew cache: `~/Library/Caches/Homebrew`
- npm cache and logs: `~/.npm/_cacache`, `~/.npm/_logs`
- Gradle caches: `~/.gradle/caches`, `~/.gradle/daemon`, `~/.gradle/wrapper/dists`
- Discovered project `node_modules` directories

Report-only locations:

- Docker Desktop logs: `~/Library/Containers/com.docker.docker/Data/log`
- Docker Desktop VM data: `~/Library/Containers/com.docker.docker/Data/vms`

Docker VM data is intentionally report-only because deleting it directly can remove images, containers, and volumes. Use Docker's own prune commands for Docker cleanup.

## Safety Model

- `scan` and `report` never delete files.
- `clean` fails unless you pass at least one explicit category flag.
- `--node-modules` requires `--older-than`, such as `60d`.
- Fixed cache directories use contents-only cleanup, preserving the parent directory.
- `node_modules` cleanup removes the selected `node_modules` directory tree.
- Symlink targets are refused.
- Docker data is report-only.
- Use `--dry-run` before deleting to see the selected paths.

Supported age values are `s`, `m`, `h`, `d`, and `w`, for example `30d`, `12h`, or `2w`.

## xcode-sim-prune

This repository also includes `xcode-sim-prune`, a focused CLI for Xcode simulator storage. It uses `xcrun simctl` for simulator operations instead of deleting simulator internals directly.

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
- `delete-unavailable` delegates to `xcrun simctl delete unavailable`.
- `delete-runtimes` requires `--older-than` and delegates to `xcrun simctl runtime delete --notUsedSinceDays`.
- `erase-unused` never erases booted devices.
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
