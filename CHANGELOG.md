# Changelog

All notable changes to this project will be documented in this file.

## 0.1.0 - 2026-06-06

Initial open-source release.

- Added `mac-dev-clean` with `scan`, `clean`, and `report` commands.
- Added safe cleanup support for Xcode DerivedData, simulator caches, Homebrew cache, npm cache/logs, Gradle caches, and aged `node_modules`.
- Added report-only Docker Desktop storage visibility.
- Added `xcode-sim-prune` for focused CoreSimulator listing, unavailable device deletion, old runtime deletion, and unused simulator erase workflows.
- Added dry-run mode, JSON output, human-readable tables, explicit deletion flags, and age filters.
- Added safety-root validation, known cache path-shape checks, symlink refusal, and malformed simulator UDID refusal.
- Added unit tests, macOS GitHub Actions CI, MIT licensing, contributing guidance, and a security policy.

