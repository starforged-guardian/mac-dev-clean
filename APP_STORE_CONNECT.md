# App Store Connect Content

This is the English (U.S.) metadata draft for the native macOS app.

## Submission status: blocked for the Mac App Store

Do not upload the current build to App Store Connect yet.

The existing app is intentionally not App Sandbox-enabled because it scans and
cleans developer caches across the user's Library. It also launches Python 3
from Xcode Command Line Tools. Mac App Store apps must be sandboxed,
self-contained app bundles and must not depend on optionally installed
technologies.

The current build is suitable for direct Developer ID distribution using the
workflow in [DISTRIBUTING.md](DISTRIBUTING.md). Use the metadata below after an
App Store-specific build has been implemented and tested.

### Required product changes

1. Add an App Store target with App Sandbox enabled.
2. Replace broad automatic file access with user-selected folder access and
   security-scoped bookmarks, or obtain and fully justify every required
   temporary exception entitlement to Apple.
3. Make the app self-contained. Rewrite the cleanup engine in Swift or embed
   and sign every required runtime/helper instead of launching
   `/usr/bin/python3` from Command Line Tools.
4. Remove or redesign cleanup operations that cannot function inside App
   Sandbox, including any unsupported external-process or system-cache access.
5. Test the archived App Store build using a clean macOS user account without
   Xcode or Command Line Tools installed.
6. Add the App Store provisioning profile, distribution signing, sandbox
   entitlements, and an accurate export-compliance declaration.
7. Update this metadata if the sandboxed edition supports fewer cleanup
   categories than the direct-download edition.

## App information

**Name**  
mac-dev-clean

**Subtitle**  
Reclaim developer disk space

**Bundle ID**  
`com.ravenvector.mac-dev-clean`

**SKU**  
`RAVENVECTOR-MAC-DEVCLEAN-MACOS`

**Primary language**  
English (U.S.)

**Primary category**  
Developer Tools

**Secondary category**  
Utilities

**Copyright**  
`2026 [Legal name shown on the Apple Developer account]`

Do not enter “Raven Vector” in the copyright field unless that is the person or
legal entity that owns the app rights. App Store Connect adds the copyright
symbol automatically.

**Price**  
Free — recommended for the initial open-source release. Confirm this business
decision before creating the version.

**Digital Services Act status**  
Choose trader or non-trader based on the Apple Developer account owner's actual
commercial status. If distributing in the EU as a trader, complete Apple's
identity, address, phone, and email verification; do not copy a guessed answer
from this document.

**License agreement**  
Apple's standard EULA.

## URLs

**Support URL**  
`https://www.ravenvector.com/contact`

**Marketing URL**  
`https://www.ravenvector.com/`

**Privacy Policy URL**  
`https://www.ravenvector.com/privacy`

Before submission, verify that the support page visibly provides a monitored
email address or other legally required contact information. An app-specific
marketing and privacy page would be preferable; suggested paths are:

- `https://www.ravenvector.com/mac-dev-clean`
- `https://www.ravenvector.com/mac-dev-clean/privacy`

Do not enter those app-specific URLs until real pages are published at them.

## Promotional text

See what developer caches are using your Mac's storage, choose exactly what to
clean, and reclaim space with local, review-first controls.

## Description

Developer tools are productive. Their caches are not.

mac-dev-clean helps you understand where developer storage is going and reclaim
space without relying on mysterious terminal commands. Scan supported cache
locations, review each cleanup group, choose exactly what to remove, and confirm
before anything is deleted.

FIND THE BIG SPACE USERS

See storage used by build artifacts, simulator caches, device support files,
package-manager caches, browser models and caches, editor caches, logs, and
other developer-generated data.

REVIEW BEFORE CLEANUP

Cleanable locations are grouped by purpose and can be expanded to show their
individual paths and sizes. Select all groups or keep complete control by
choosing them one at a time.

KEEP IMPORTANT DATA SEPARATE

Archives, device backups, project history, and other sensitive locations remain
review-only. mac-dev-clean can reveal them in Finder but never includes them in
automatic cleanup.

PRIVATE BY DESIGN

Scanning happens locally on your Mac. mac-dev-clean has no accounts, analytics,
advertising, tracking, or telemetry. File paths and scan results are not sent to
Raven Vector or any third party.

BUILT FOR SAFER CLEANUP

- Opening the app performs a read-only scan.
- Cleanup requires an explicit selection and macOS confirmation.
- Supported targets are constrained to known cache locations.
- Symlinked or malformed cleanup targets are refused.
- Generated caches can be rebuilt or downloaded again by their original tools.

For best results, close active developer tools before cleaning their caches.
Disk-space reclamation can take additional time when macOS and APFS are
releasing shared simulator data.

Requires macOS 14 or later.

## Keywords

`developer tools,cache cleaner,disk space,simulator,build artifacts,storage,cleanup,mac utility`

Do not add competitor, company, or third-party app names to the keyword field.

## Version information

**Recommended first App Store version**  
1.0.0

The current project version is 0.5.0. Bump it to 1.0.0 only after the sandboxed,
self-contained App Store edition is complete so version metadata stays aligned
with the binary.

**Build**  
1

**What's New**  
Leave blank for the first App Store version. App Store Connect does not provide
this field for an app's first version.

Suggested text for the first update:

> Improved cleanup discovery and review controls, expanded native macOS
> guidance, and refined safety checks for developer cache cleanup.

**Release option**  
Manual release is recommended for version 1.0 so the product page and support
site can be checked after approval before the app goes live.

## App privacy

Provided the App Store build remains consistent with the audited source:

**Does this app or its third-party partners collect data?**  
No, we do not collect data from this app.

Rationale:

- Paths, sizes, and scan results remain on the device.
- There is no analytics, telemetry, advertising, account, or crash-reporting
  SDK.
- The About-page website link is opened by macOS only after the user chooses it.
- Opening a website is not app data collection by the native app.

Re-audit this answer whenever networking, crash reporting, analytics, support
forms, accounts, or third-party SDKs are added.

## Age rating questionnaire

Expected answers for the current app are **None** or **No** for all content and
capability questions, including violence, mature themes, gambling, sexual
content, profanity, medical content, unrestricted web access, messaging,
advertising, user-generated content, and social features.

The expected result is Apple's lowest general audience rating. Complete the
live questionnaire from the actual submitted build because Apple may revise the
questions and regional results.

## Content rights

The app does not display or stream third-party editorial content. It references
developer tools and compatible products descriptively. Confirm that Raven
Vector owns or has distribution rights for the submitted app icon and bundled
logo artwork before answering the content-rights declaration.

**Recommended third-party content answer**  
No, the app does not contain, show, or access third-party content. Revisit this
answer if the App Store edition begins displaying file contents, downloaded
material, remote feeds, or third-party media rather than local cache metadata.

## Export compliance

The current app implements no encryption and contains no networking stack. The
About page asks macOS to open an HTTPS website in the user's default browser.

For the current feature set, the anticipated answer is that the app does not
implement non-exempt encryption. Confirm this against the final linked binary
and any newly added SDKs before submission. If still accurate, set
`ITSAppUsesNonExemptEncryption` to `NO` in the App Store target's Info.plist to
avoid answering the same export-compliance question for every upload.

## App Review information

**Sign-in required**  
No

**Contact**  
Enter a monitored name, email address, and phone number for someone who can
answer technical questions during review.

**Review notes — use only after the sandboxed build is complete**

> mac-dev-clean is a local developer-storage inspection and cleanup utility. It
> does not require an account, network connection, subscription, or in-app
> purchase.
>
> On first launch, the app performs a read-only scan of the folders the user has
> explicitly authorized. The Cleanup screen groups supported cache locations.
> Expand a group to inspect its paths, select one or more groups, choose Clean
> Selected, and confirm the destructive action in the macOS dialog. The Review
> Only screen contains locations that the app never sends to the cleanup path.
>
> To exercise cleanup safely, create disposable cache files in an authorized
> test folder or use the existing cache data on the review Mac. Please close
> active developer tools before cleaning. Reclaiming shared simulator storage
> may not be reflected immediately by APFS.
>
> All scanning and cleanup happen locally. The app collects no data and includes
> no analytics, advertising, tracking, crash-reporting, or account SDKs. The
> ravenvector.com link on the About screen opens only when selected.
>
> App Sandbox access: [replace this paragraph with the exact user-selected file
> workflow and every temporary exception entitlement in the submitted build].

Never submit the bracketed placeholder. If temporary exception entitlements are
used, include each key, each path value, why it is essential, exact reviewer
steps, and the related Feedback Assistant ID in App Store Connect's App Sandbox
information.

## Screenshot plan

Use five or six clean screenshots at 2880 × 1800 pixels. Apple accepts Mac
screenshots in a 16:10 aspect ratio at 1280 × 800, 1440 × 900, 2560 × 1600, or
2880 × 1800 pixels.

Capture realistic but sanitized paths. Do not expose a username, customer name,
private repository, device identifier, signing identity, or Apple Account.

1. **See where developer storage goes** — Cleanup overview with meaningful
   cleanable and review-only totals.
2. **Choose exactly what to clean** — Several cleanup groups selected, with a
   useful range of cache categories.
3. **Inspect every location** — One expanded group showing sanitized paths,
   individual sizes, notes, and Reveal controls.
4. **Confirm before removal** — Native cleanup confirmation dialog with a
   realistic selected total.
5. **Keep important data review-only** — Review Only page showing archives or
   backups and the explanatory safety copy.
6. **Private, local, and open source** — About page with version and Raven
   Vector link. Use this only after the first five clearly demonstrate utility.

Avoid claiming a specific number of gigabytes will always be recovered. APFS
clone sharing and delayed reclamation mean logical sizes can differ from space
immediately returned to the disk.

## Final submission checklist

- [ ] App Store-specific sandboxed build works without Xcode, Command Line
      Tools, Homebrew, or another separately installed runtime.
- [ ] Product description matches the reduced capabilities of that build.
- [ ] Bundle ID is `com.ravenvector.mac-dev-clean` everywhere.
- [ ] Version and build number match App Store Connect.
- [ ] App category is Developer Tools in both Xcode and App Store Connect.
- [ ] App-specific privacy and support URLs are live and show real content.
- [ ] App privacy answer has been re-audited from the final binary.
- [ ] Logo and icon distribution rights are confirmed.
- [ ] No placeholder text remains in metadata or review notes.
- [ ] Screenshots contain no private paths or identifiers.
- [ ] Sandbox entitlement usage information is complete.
- [ ] The archived build passes local validation and TestFlight review testing.
