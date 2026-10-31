# Contributing to MailPort

## Set up

You need Xcode with Swift 6 on an Apple silicon Mac.

```sh
./scripts/build.sh --test
```

This runs the Swift tests and writes a locally signed app to `dist/MailPort.app`. No Apple certificate is needed. Local builds aren't notarized, so they only run on the Mac that built them.

| Variable | Effect |
| --- | --- |
| `MAILPORT_BUILD_DIR` | Where build caches go |
| `MAILPORT_DIST_DIR` | Where the app is written |
| `MAILPORT_SIGN_IDENTITY` | Signs with a named certificate instead of locally |
| `MAILPORT_PREVIEW_DATA_DIR` | Test profile folder for debug builds; release builds ignore it |

## Run from Xcode

Open `MailPort.xcodeproj` and select the **MailPort** scheme. ⌘R runs **MailPort Dev**, and ⌘U runs the Swift tests.

The project signs with team `WDCGJTU726`. If you aren't on that team, select your own under Signing & Capabilities on the MailPort and MailPortEmbeddedTests targets, and don't commit that change.

`project.yml` is the source of the Xcode project. After adding, removing, or renaming files, install [XcodeGen](https://github.com/yonaskolb/XcodeGen) and regenerate:

```sh
brew install xcodegen
xcodegen generate
```

Signing settings changed only in Xcode are lost when the project is regenerated, so put lasting changes in `project.yml`.

### Your real data stays separate

Debug builds never open the real profile, whatever their bundle identifier. They use `MailPortSecurityTest-securityqa` in Application Support, or `MAILPORT_PREVIEW_DATA_DIR`. You'll sign in again the first time, and MailPort Dev can run beside your installed copy.

The Release configuration uses your real accounts, so don't switch the Run action to it for testing.

## Test

```sh
./scripts/build.sh --test
node --test scripts/test-tab-activity.cjs scripts/test-notification-bridge.cjs
```

Tests must not reach the network or real accounts. Use a disposable directory named `MailPortSecurityTest-*` and fixture accounts, as the existing tests do. Add a regression test with each bug fix.

## Project layout

| Path | Contents |
| --- | --- |
| `Sources/MailPortCore` | Accounts, tabs, pins, Go To, link routing, and other logic without UI |
| `Sources/MailPortSecurity` | PIN lock engine and local data reset |
| `Sources/MailPortEmbedded` | The app: SwiftUI views, web views, and page bridges |
| `Sources/MailPortEmbedded/Resources` | Scripts injected into Gmail and Calendar pages |
| `Resources` | `Info.plist` and entitlements |
| `scripts` | Build, release, and icon scripts, plus JavaScript tests |
| `SingleWindowPreview` | Retired; the app lives at the repository root |

## Rules to keep

**Don't change Google's pages.** MailPort doesn't hide warnings or restyle pages with CSS or scripts. Page scripts only observe, and only on top-level HTTPS pages on `mail.google.com` and `calendar.google.com`.

**Keep the stored identifiers.** The bundle identifier `com.chriswilson.mailport.embedded`, WebKit store identifiers, preferences domain, and `MailPortPreview` support folder must not change, or users lose their sign-ins and settings. Fields added to `accounts.json` must be optional, because older builds still need to read it.

**Keep account data separate.** Each account has an identifier-backed `WKWebsiteDataStore`, and its services share that store. Never move data between stores.

**Keep bad data contained.** One invalid saved value shouldn't block the account list. Reject bad input in the editor, and fall back safely when loading.

**Clear state when locking.** Anything new that holds account data must be cleared in `suspendForLock()` and covered by the local data reset.

**Protect the PIN lock.** PINs are stored only as a salted PBKDF2-HMAC-SHA256 verifier with 200,000 rounds, and the verifier and failure counter live in the Keychain. Missing or unreadable security records leave the app locked.

**Stay honest about the browser identity.** For known WebKit builds, the user agent adds conservative Safari version tokens while keeping the `MailPortPreview` identity. Unknown builds keep the plain identity. This helps sites detect the browser version, but doesn't provide official support, extra browser features, or passkeys. Passkeys need an associated domain or Apple's managed browser entitlement.

## Screenshots

Never capture real accounts or mail. Use a debug build with a disposable profile and fake accounts using `.example` addresses, and check the image before committing it.

## Release

Maintainers publish from a clean `main` that matches `origin/main`.

```sh
./scripts/release.sh --dry-run   # Build and package only; no Apple or GitHub steps
./scripts/release.sh             # Release the next patch version after the latest tag
./scripts/release.sh 0.7.0       # Release a specific version
```

The script runs the tests, signs and notarizes the app, builds a stapled disk image in `dist/release/`, tags the commit, and publishes a GitHub release. Versions stay on `0.x.y`. With no version, it adds one to the latest `v0.x.y` tag unless `Resources/Info.plist` already has a higher version. The build number goes up whenever the version changes.

Don't commit anything while a release is running. A version bump committed mid-run is accepted, but any other commit stops the release before it publishes, because the tag wouldn't match what was built. Dry-run disk images aren't notarized, so don't share them.

### One-time setup

1. Create a **Developer ID Application** certificate. This needs a paid Apple Developer Program membership, and only the team's Account Holder can create one. Back up its private key.
2. Create an app-specific password at [account.apple.com](https://account.apple.com), then save the notary credentials:

   ```sh
   xcrun notarytool store-credentials mailport-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
   ```

`MAILPORT_SIGN_IDENTITY`, `MAILPORT_NOTARY_PROFILE`, and `MAILPORT_RELEASE_REPO` override the certificate, notary profile, and target repository.

Moving from a local build to a Developer ID build changes the app's signature, so macOS may ask again for Keychain, notification, camera, and microphone access. Later Developer ID releases keep the same identity.
