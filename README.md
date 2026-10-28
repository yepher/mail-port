# MailPort

A native macOS app that puts Gmail, Calendar, and other Google services directly inside one macOS window. Each account gets Mail and Calendar tabs in a compact, color-coded strip, matching the essential Mailplane behavior in the reference screenshot. Switching tabs keeps the page alive. Google service tabs do not launch Chrome. External links can open the default browser.

**This remains a compatibility preview.** The user completed Google sign-in for two accounts on this Mac during testing. Gmail and the account's Calendar have loaded inside the same window. Google may still reject embedded browsers or require additional identity checks; this result is not a guarantee for every account or future sign-in.

## Run

Open `dist/MailPort.app`. It requires Apple silicon and macOS 14 or later. The build is signed locally and is not notarized for public distribution.

This is the sole active MailPort implementation. Add accounts and sign in on Google's page inside each account's Mail tab. The label alone does not authenticate an account. Existing accounts and sign-ins from the single-window preview are preserved.

Each account uses an identifier-backed persistent `WKWebsiteDataStore`. Its Mail and Calendar tabs share the same store; other accounts have separate stores. WebKit owns website data storage. The preview does not export credentials or copy Chrome cookies. Account labels are saved in `~/Library/Application Support/MailPortPreview/accounts.json`.

Use the toolbar to go back, forward, reload, return to the service home page, compose, or open another Google service in an in-app tab. Right-click an account tab to edit its label/color or remove its tabs. Removing account tabs preserves the website session.

Drag any tab left or right over another tab to rearrange it. Each tab moves independently, including Mail and Calendar tabs for the same account. Reordering keeps the active page loaded and saves the new order for the next launch.

Every tab has an × close button and a Close Tab context-menu action. ⌘W closes the active tab; ⇧⌘T reopens the last closed tab. Closing a tab preserves its account sign-in. Open tabs are restored across app restarts, including an intentionally empty tab strip. Reopen services for any saved account from the Google Apps menu.

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

The single-window implementation lives at the repository root. Run builds and tests here; `SingleWindowPreview` is no longer a separate project. The retired multi-window launcher is archived outside the active repository.

The bundle identifier `com.chriswilson.mailport.embedded`, the existing WebKit store identifiers, preferences domain, and `MailPortPreview` support directory are deliberately retained so promoting the app does not reset sign-ins or tab settings.

## Verified in version 0.2.1

On this Mac, all 17 core and browser-identity tests passed. After restarting with the compatibility suffix, Gmail and Calendar loaded with the saved sign-in and neither displayed the unsupported-browser warning. Calendar opened an unsaved event editor with an enabled Save button; the empty draft was closed without saving. Actual event writes, notification delivery, passkeys, and broader daily functionality are not validated by that check.

Sources: [Google supported browser guidance](https://support.google.com/accounts/answer/7675428), [Google OAuth secure-browser policy](https://developers.google.com/identity/protocols/oauth2/policies), [Apple identifier-backed website data stores](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/init(foridentifier:)), [Apple passkey requirements](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys), [WebKit's macOS user-agent issue](https://bugs.webkit.org/show_bug.cgi?id=278284), and [Apple Safari 26.4–26.6 release notes](https://developer.apple.com/documentation/safari-release-notes/safari-26_4-release-notes).

## Verified in version 0.2.2

All 26 tests passed. In the running app, the × button closed a background tab, Command-W closed the active tab while keeping the window open, and closing the last tab showed an empty workspace with reopen controls. Shift-Command-T restored closed tabs. Existing account sign-ins were preserved.

## Verified in version 0.2.3

All 29 tests passed. Native UI checks moved a tab from first to last, verified the reordered strip after restarting the app, and moved it back from last to first. Existing tab identities, account sessions, and the active page remain intact while reordering.

## Version 0.2.4

Gemini is available in Google Apps, every account submenu, and Navigate. It opens gemini.google.com/app as an in-app tab using that account’s existing website data store. Gemini tabs support closing, reopening, rearranging, and restoring across launches like other service tabs.

Validation: all 29 tests passed after adding Gemini. The Google Apps menu showed Gemini for the current account and all account submenus. Selecting it opened Google Gemini at gemini.google.com/app in the same app window with the existing selected-account sign-in. No prompt submission was needed for this check.

## Version 0.3.0

The single-window application is now the main MailPort project and builds as `dist/MailPort.app`. The old Chrome launcher has been retired. This organizational change does not remove the existing limitations listed above.
