# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

- Reworked human-readable scan and cleanup output into summary, quick-win, cleanable, and review-only sections with spaced two-line entries, wrapped notes, and home-relative paths.
- Suppressed report-only locations under 1 MiB so empty directories such as an unused MobileSync backup folder are not presented as meaningful review items.

- Added scanning and dry-run-first cleanup for `~/Library/Developer/XCTestDevices`, where parallel Xcode tests can leave hundreds of multi-gigabyte simulator clones.
- Delegated XCTest clone deletion to `simctl` with the dedicated device set instead of deleting simulator internals directly, and refuse cleanup while any clone is booted.
- Added Xcode device-log cleanup plus `--xcode-caches` as a broad explicit cleanup option for supported data under `~/Library/Developer`.
- Kept the no-argument `mac-dev-clean` shortcut inclusive of XCTest clone cleanup, with regression coverage so no explicit category flag is required.
- Stopped presenting the sum of `simctl` XCTest clone logical sizes as reclaimable disk usage; clone storage is now labeled `shared/unknown` because APFS sharing can make the logical total vastly exceed physical allocation.
- Updated `run_local.sh` to invoke the standard one-confirmation cleanup instead of hard-coding clone-only commands.
- Report XCTest clone cleanup as an asynchronous delete request and explain that CoreSimulator/APFS free-space reclamation may lag for several minutes.
- Added supported `simctl` cleanup for system-wide CoreSimulator dyld shared caches.
- Added cleanup for Chrome's downloaded on-device AI model, browser component/update caches, Cursor/Windsurf/Codex desktop caches, Bun's install cache, and downloaded aerial wallpapers.
- Added strict discovery and path-marker validation for project-local Xcode DerivedData directories.
- Added report-only guidance for Codex history/generated images, local Apple device backups, Command Line Tools, and safe manual iCloud offloading.

## 0.4.0 - 2026-06-07

- Skipped cleanable scan targets under 1 MiB to avoid recommending no-op cleanup for tiny cache directories.
- Added cleanup support for Xcode documentation and DeviceSupport caches, pnpm and other package/tool caches, browser caches, plus report-only surfacing for Xcode Archives and Codex runtime caches.
- Added `xcode-sim-prune delete-devices` for dry-run-first deletion of selected shutdown simulator devices by exact name or UDID.
- Made `xcode-sim-prune` without arguments scan safe simulator device cleanup candidates and prompt before deleting anything.
- Updated the no-argument `xcode-sim-prune` scan to prioritize meaningful wins by skipping tiny never-booted devices and including shutdown devices that are at least 1 GB.
- Added an immediate `mac-dev-clean` scan progress message so slow disk usage scans do not leave users staring at a silent terminal.
- Added cleanable/report-only scan totals and top dry-run command suggestions to human and JSON scan output.

## 0.1.0 - 2026-06-06

Initial open-source release.

- Added `mac-dev-clean` with `scan`, `clean`, and `report` commands.
- Added safe cleanup support for Xcode DerivedData, simulator caches, Homebrew cache, npm cache/logs, Gradle caches, and aged `node_modules`.
- Added report-only Docker Desktop storage visibility.
- Added `xcode-sim-prune` for focused CoreSimulator listing, unavailable device deletion, old runtime deletion, and unused simulator erase workflows.
- Added dry-run mode, JSON output, human-readable tables, explicit deletion flags, and age filters.
- Added safety-root validation, known cache path-shape checks, symlink refusal, and malformed simulator UDID refusal.
- Added unit tests, macOS GitHub Actions CI, MIT licensing, contributing guidance, and a security policy.
