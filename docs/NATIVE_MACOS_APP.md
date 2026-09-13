# Native macOS App

The native app is a SwiftUI front end for the same reviewed Python cleanup
engine used by the command-line tools. It is intended for developers who want
to inspect and clean disk usage without remembering category flags.

## Safety and privacy

- Opening the app performs a read-only scan. It does not clean automatically.
- The startup scan excludes project discovery, `node_modules`, and protected
  user folders such as Documents, Desktop, and Downloads.
- Cleanup is limited to the cleanable groups selected in the UI and requires a
  native macOS confirmation immediately before deletion.
- Review-only locations can be revealed in Finder but are never sent to the
  cleanup command. The latest Xcode archive for each app stays review-only;
  older archive copies appear in Cleanup only after they are classified as
  extras.
- Project Shelf moves only a complete project folder after an explicit
  confirmation. It records both locations and restores to the original path;
  it never deletes or re-clones repository contents.
- iCloud Drive controls upload and eviction. The app can move a project into the
  user's iCloud Drive folder, but it does not claim space was reclaimed until
  macOS evicts the local download. External-volume shelves reclaim internal SSD
  space directly.
- Paths, file sizes, and scan results stay on the Mac. The app has no analytics,
  telemetry, advertising, or automatic network requests. The Raven Vector link
  opens the website only when the user chooses it.
- The app launches Python directly, without a shell. It clears inherited
  `PYTHON*` settings, uses only the bundled engine path, and disables user-site
  packages.

The app is not App Sandbox-enabled because its purpose requires access to
developer caches across the user's Library. It should not require Full Disk
Access for its normal scan. macOS may still enforce permissions for locations
outside the app's supported automatic scan.

## Review simulator storage

Choose **Simulators**, or **Review large simulator devices** on Cleanup or Review
Only. Devices are sorted by reported size and show their name, runtime, state,
last boot, and UUID so you can match large folders from a disk-usage tool.

Use **Delete Device…** only for a device whose local apps and test data you no
longer need. The confirmation identifies the exact device and explains that its
data cannot be recovered. Active or transitioning devices cannot be deleted;
the Python engine checks the live state immediately before requesting deletion
of that one UUID. No device is selected automatically, and the app never shuts
down a simulator or deletes its installed runtime. Keep your useful phone,
tablet, and TV configurations for testing.

Reported device sizes can include shared APFS data and are not a promise of
reclaimed bytes. Free space refreshes after each deletion. This screen is
separate from cache cleanup and does not require runtime-image management to
succeed. If Xcode's simulator service fails, refresh after it becomes available.

Busy browser caches may be recreated while a browser runs. Cleanup continues
with other entries and reports any skipped entries; quit the owning browser,
then scan and clean again. It does not terminate the browser or repeatedly chase
new cache files.

## Architecture

The app source lives in `macos/Sources/MacDevCleanApp`. `Backend.swift` launches
`python3 -m mac_dev_clean` and decodes JSON reports into the Swift models. Both
the Xcode build and the shell build embed `src/mac_dev_clean` under the app's
Resources directory before signing.

The UI intentionally passes explicit cleanup flags for selected cleanable
groups. It never invokes the CLI's broad no-argument shortcut. This keeps the
confirmation dialog and the backend operation aligned with what is visible in
the app.

`RepositoryShelf.swift` owns project discovery, allocated-size measurement,
catalog persistence, exact-folder moves, and restoration. `RepositoryShelfView`
surfaces active and shelved projects. The catalog is stored under Application
Support; project data remains in the user-selected folder. Moving the complete
folder, rather than treating a remote Git server as a backup, preserves ignored
files and other local-only state.

## Run and test locally

Launch a locally built app:

```sh
./run_gui.sh
```

Run the Swift tests:

```sh
swift test --package-path macos
```

Build the committed Xcode project without signing:

```sh
xcodebuild \
  -project macos/MacDevClean.xcodeproj \
  -scheme MacDevCleanApp \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Python 3 from Xcode Command Line Tools is required on the destination Mac.

## Xcode project

`macos/project.yml` is the source of truth for the generated Xcode project.
After changing targets, resources, build settings, or build phases, regenerate
the project and review the resulting diff:

```sh
xcodegen generate --spec macos/project.yml
```

Do not commit `.swiftpm`, `xcuserdata`, `*.xcuserstate`, DerivedData, archives,
signing certificates, provisioning profiles, Team IDs, Apple Account email
addresses, or notarization credentials. The shared project and scheme are safe
to commit; personal signing selection belongs in ignored Xcode user state.

For Developer ID signing and notarization, see [DISTRIBUTING.md](../DISTRIBUTING.md).

## Resource checklist

When adding a bundled resource:

1. Add it to `macos/project.yml` and regenerate the Xcode project.
2. Add the equivalent copy step to `scripts/build_macos_app.sh`.
3. Confirm the built app contains the resource.
4. Confirm the resource's license permits public redistribution.
