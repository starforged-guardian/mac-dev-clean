# Distributing the macOS App

> **Distribution choice:** The current app is designed for direct Developer ID
> distribution because it is not App Sandbox-enabled and needs broad access to
> developer caches. It is not eligible for the Mac App Store as currently
> implemented. See [APP_STORE_CONNECT.md](APP_STORE_CONNECT.md) for the metadata
> draft and required App Store-specific product changes.

The release scripts build a universal app, sign it with a Developer ID
Application certificate and hardened runtime, submit it to Apple's notary
service, staple the ticket, verify it with Gatekeeper, and create a ZIP suitable
for direct download.

## Xcode workflow

Open `macos/MacDevClean.xcodeproj`, select the `MacDevCleanApp` target, and use
the Signing & Capabilities tab to choose your Apple Developer team. The target
already has these distribution settings:

- Bundle identifier `com.ravenvector.mac-dev-clean`
- Automatic signing
- Hardened runtime
- Universal Release architecture settings for Apple silicon and Intel
- Marketing and build versions exposed in Xcode
- A shared scheme with the native unit tests
- A build phase that embeds the Python cleanup engine before code signing

Choose Product > Archive. In Organizer, select **Distribute App**, then
**Developer ID** and **Upload** to let Xcode sign and submit the archive to
Apple's notary service. After Apple accepts it, export the notarized app for
distribution.

The command-line workflow below remains available for automated releases.

## 1. Install a Developer ID Application certificate

Create a **Developer ID Application** certificate using Apple's
[Developer ID certificate workflow](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/),
then install the downloaded certificate in Keychain Access. The matching private
key must be present on this Mac.

Verify it locally:

```sh
security find-identity -v -p codesigning
```

The output must include an identity beginning with `Developer ID Application:`.
A Developer ID Installer certificate is not needed because this project ships a
ZIP rather than an installer package.

## 2. Store notarization credentials securely

Create an app-specific password for your Apple Account, then run:

```sh
NOTARY_APPLE_ID="you@example.com" \
APPLE_TEAM_ID="ABCDEFGHIJ" \
./scripts/configure_notarization.sh
```

The script asks for the app-specific password through `notarytool` and stores it
in the login Keychain as `mac-dev-clean-notary`. The password is never written
to this repository or passed as a command-line argument.

Set `NOTARYTOOL_PROFILE` if you prefer a different Keychain profile name.

## 3. Build, sign, notarize, and package

```sh
./scripts/notarize_macos_app.sh
```

If multiple Developer ID identities are installed, select one explicitly:

```sh
MACOS_SIGNING_IDENTITY="Developer ID Application: Your Name (ABCDEFGHIJ)" \
./scripts/notarize_macos_app.sh
```

The default build contains both `arm64` and `x86_64` slices and targets macOS
14 or newer. Override those only when intentionally producing a narrower build:

```sh
MACOS_ARCHS="arm64" MACOS_DEPLOYMENT_TARGET="14.0" \
./scripts/notarize_macos_app.sh
```

The final artifact is written to:

```text
dist/mac-dev-clean-VERSION-macos.zip
```

The ZIP is created after stapling, so the app retains its offline notarization
ticket when another user downloads and expands it.

## Verification performed by the script

- Developer ID signing with hardened runtime and a secure timestamp
- Universal executable architecture check during the app build
- Synchronous `notarytool` submission with an explicit Accepted-status check
- Notarization ticket stapling and validation
- Strict code-signature validation
- Gatekeeper assessment with `spctl`
- SHA-256 checksum output for the final ZIP

The app is distributed outside the Mac App Store and is not sandboxed. It does
not need a provisioning profile because it currently uses no restricted Apple
capabilities. Python 3 from Xcode Command Line Tools is still required on the
destination developer Mac.

Apple's current command-line workflow is documented in
[Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
