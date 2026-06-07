# Changelog

All notable changes to this project will be documented in this file.

## 0.3.0 - 2026-06-07

- Skipped cleanable scan targets under 1 MiB to avoid recommending no-op cleanup for tiny cache directories.
- Added cleanup support for Xcode documentation and DeviceSupport caches, pnpm and other package/tool caches, browser caches, plus report-only surfacing for Xcode Archives and Codex runtime caches.
- Added `xcode-sim-prune delete-devices` for dry-run-first deletion of selected shutdown simulator devices by exact name or UDID.
- Made `xcode-sim-prune` without arguments scan safe simulator device cleanup candidates and prompt before deleting anything.

## 0.1.0 - 2026-06-06

Initial open-source release.

- Added `mac-dev-clean` with `scan`, `clean`, and `report` commands.
- Added safe cleanup support for Xcode DerivedData, simulator caches, Homebrew cache, npm cache/logs, Gradle caches, and aged `node_modules`.
- Added report-only Docker Desktop storage visibility.
- Added `xcode-sim-prune` for focused CoreSimulator listing, unavailable device deletion, old runtime deletion, and unused simulator erase workflows.
- Added dry-run mode, JSON output, human-readable tables, explicit deletion flags, and age filters.
- Added safety-root validation, known cache path-shape checks, symlink refusal, and malformed simulator UDID refusal.
- Added unit tests, macOS GitHub Actions CI, MIT licensing, contributing guidance, and a security policy.
