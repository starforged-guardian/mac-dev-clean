# Open Source Publication Audit

This document records the repository's publication review as of 2026-07-11 and
provides a repeatable checklist for future pushes. It is an engineering review,
not a guarantee against every possible secret or a substitute for legal advice.

## Audit result

The tracked history and current public candidate files were scanned with
Gitleaks in redacted mode. No credentials or high-confidence secrets were
reported. A separate filename and content review found no signing keys,
provisioning profiles, notarization passwords, personal Xcode user state, or
machine-specific `/Users/<local-user>` paths in files eligible for publication.

The repository is configured to exclude:

- `.env` files and common private-key, certificate, provisioning, and Keychain
  exports;
- SwiftPM/Xcode user state, archives, result bundles, dSYMs, DerivedData, and
  local build output;
- notarization logs, which can contain account or submission metadata;
- layered Raven Vector artwork and unused logo variants that are not required
  by the app.

The four required Raven Vector and mac-dev-clean brand files remain
intentionally public so the app builds from a fresh checkout. They are
expressly excluded from the MIT License and governed by
[BRANDING.md](../BRANDING.md). The publication audit verifies that each file is
listed there, and app builds bundle both `LICENSE` and `BRANDING.md` alongside
the assets.

## Native app findings

- Scan and cleanup use the local Python engine; no shell command is constructed.
- The app clears inherited `PYTHON*` settings, sets only its bundled module
  path and controlled runtime flags, and disables user-site packages.
- Startup scans omit project discovery and protected user folders.
- Review-only rows cannot become cleanup selections.
- The iCloud action opens Finder only and does not move data.
- No analytics, telemetry, advertising, updater, or automatic network client is
  present in the native UI.
- Xcode's user-script sandbox is enabled for the Python-engine copy build phase.
- CI has read-only repository permission and builds/tests the native UI without
  code signing. Third-party workflow actions are pinned to immutable commits,
  with monthly Dependabot checks for updates.

## Signing and release credentials

Developer ID private keys remain in the developer's Keychain. Notarization uses
a named `notarytool` Keychain profile. Do not add Apple Account credentials,
app-specific passwords, Team IDs, certificate exports, or profiles to scripts,
Xcode build settings, issues, logs, or documentation examples.

## Before every public push

1. Review the public file set:

   ```sh
   git ls-files --cached --others --exclude-standard
   git diff --check
   ```

   The repository helper performs these checks and runs Gitleaks when it is
   installed:

   ```sh
   ./scripts/audit_public_repo.sh
   ```

2. Search both the pending tree and history with a maintained secret scanner:

   ```sh
   gitleaks detect --source . --no-git --redact
   gitleaks detect --source . --redact
   ```

3. Confirm Xcode user state and signing material are ignored:

   ```sh
   git status --ignored --short macos
   git check-ignore macos/.swiftpm/example macos/MacDevClean.xcodeproj/xcuserdata/example
   ```

4. Run the Python tests, Swift tests, and unsigned Xcode build documented in
   [NATIVE_MACOS_APP.md](NATIVE_MACOS_APP.md).

5. Inspect generated reports and screenshots before attaching them to GitHub;
   paths can reveal usernames, private project names, and customer information.

If a credential ever reaches Git history, rotate or revoke it first. Removing a
file from the latest commit does not invalidate an exposed credential.
