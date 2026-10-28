# MailPort — single-window preview

A separate experimental build that puts Gmail, Calendar, and other Google services directly inside one macOS window. Each account gets Mail and Calendar tabs in a compact, color-coded strip, matching the essential Mailplane behavior in the reference screenshot. Switching tabs keeps the page alive. Google service tabs do not launch Chrome. External links can open the default browser.

**This remains a compatibility preview.** The user completed Google sign-in for two accounts on this Mac during testing. Gmail and the account's Calendar have loaded inside the same window. Google may still reject embedded browsers or require additional identity checks; this result is not a guarantee for every account or future sign-in.

## Run

Open `dist/MailPort Preview.app`. It requires Apple silicon and macOS 14 or later. The build is signed locally and is not notarized for public distribution.

Account labels are imported once from the original MailPort's account list. The original app and its Chrome data remain untouched. Sign in again on Google's page inside each account's Mail tab. The label alone does not authenticate an account.

Each account uses an identifier-backed persistent `WKWebsiteDataStore`. Its Mail and Calendar tabs share the same store; other accounts have separate stores. WebKit owns website data storage. The preview does not export credentials or copy Chrome cookies. Account labels are saved in `~/Library/Application Support/MailPortPreview/accounts.json`.

Use the toolbar to go back, forward, reload, return to the service home page, compose, or open another Google service in an in-app tab. Right-click an account tab to edit its label/color or remove its tabs. Removing account tabs preserves the website session.

Shortcuts: ⌘1–9 select tabs; ⇧⌘[ / ⇧⌘] switch tabs; ⌘R reloads; ⌘N composes; ⇧⌘A adds an account. External website links open in the system browser; Google service pages and sign-in navigation remain in the app. Popups are handled in the current tab.

## Current limits

Passkeys for Google are not supported by this preview: WebKit requires a matching associated domain or Apple's managed browser passkey entitlement, neither of which is configured here. Google's existing "Try another way" flow may offer another method already configured on the account. Account security settings should remain unchanged.

Version 0.2.1 adds an experimental WebKit compatibility identity. The system WebKit build is checked against a narrow set of known engine-family release baselines from Apple's Safari release notes. For known family 624 builds, the app adds conservative Version/Safari compatibility tokens while retaining MailPortPreview's identity. The normal WebKit-generated OS/engine tokens are left unchanged. Unknown engine families keep the ordinary app identity. This targets website version detection; it does not make MailPort officially supported by Google, add missing browser APIs, or enable passkeys. No warning is hidden with CSS or page scripts.

Background notifications, native unread badges, and dependable Calendar reminders are not implemented. New permission requests, OAuth setup, security setting changes, or session exports are not used to work around Google restrictions. Browser-based OAuth for a native API client would not log Gmail's website into this WebKit store.

This preview supports native download and upload dialogs, browser navigation, JavaScript dialogs, and account/service tabs. It does not yet reproduce Mailplane's extension system or attachment tools.

## Build

With Xcode and Swift 6:

```sh
./scripts/build.sh --test
```

Set `MAILPORT_BUILD_DIR` to place build caches elsewhere. `MAILPORT_PREVIEW_DATA_DIR` selects an isolated account-label directory for testing; WebKit stores remain isolated by the app bundle identifier and account UUID.

The original launcher remains the parent project. This preview is packaged separately while browser compatibility and daily mail/calendar behavior are validated.

## Verified in version 0.2.1

On this Mac, all 17 core and browser-identity tests passed. After restarting with the compatibility suffix, Gmail and Calendar loaded with the saved sign-in and neither displayed the unsupported-browser warning. Calendar opened an unsaved event editor with an enabled Save button; the empty draft was closed without saving. Actual event writes, notification delivery, passkeys, and broader daily functionality are not validated by that check.

Sources: [Google supported browser guidance](https://support.google.com/accounts/answer/7675428), [Google OAuth secure-browser policy](https://developers.google.com/identity/protocols/oauth2/policies), [Apple identifier-backed website data stores](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/init(foridentifier:)), [Apple passkey requirements](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys), [WebKit's macOS user-agent issue](https://bugs.webkit.org/show_bug.cgi?id=278284), and [Apple Safari 26.4–26.6 release notes](https://developer.apple.com/documentation/safari-release-notes/safari-26_4-release-notes).
