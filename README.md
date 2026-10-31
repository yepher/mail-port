# MailPort

A native macOS app that puts Gmail, Calendar, and other Google services directly inside one macOS window. Each account gets Mail and Calendar tabs in a compact, color-coded strip, matching the essential Mailplane behavior in the reference screenshot. Switching tabs keeps the page alive. Google service tabs do not launch Chrome. External links can open the default browser.

**This remains a compatibility preview.** The user completed Google sign-in for two accounts on this Mac during testing. Gmail and the account's Calendar have loaded inside the same window. Google may still reject embedded browsers or require additional identity checks; this result is not a guarantee for every account or future sign-in.

## Run

Download the latest disk image from GitHub Releases, open it, and drag MailPort to Applications. For a local build, open `dist/MailPort.app`. MailPort requires Apple silicon and macOS 14 or later. Local builds are signed locally and are not notarized; only release builds can be shared with other Macs.

This is the sole active MailPort implementation. Add accounts and sign in on Google's page inside each account's Mail tab. The label alone does not authenticate an account. Existing accounts and sign-ins from the single-window preview are preserved.

Each account uses an identifier-backed persistent `WKWebsiteDataStore`. Its Mail and Calendar tabs share the same store; other accounts have separate stores. WebKit owns website data storage. The preview does not export credentials or copy Chrome cookies. Account labels are saved in `~/Library/Application Support/MailPortPreview/accounts.json`.

The sidebar groups each account's services and pinned pages, with unread counts and the Calendar event dot beside them. Select an account header to collapse it. ⌃⌘S hides the sidebar, and View → Use Tab Bar switches to the compact tab strip. The toolbar shows the current account, service, email label, and page host. Use it to go back, forward, reload, or pin the current page. On services other than Gmail it also offers New Email.

⌘T opens Go To, which finds any account, service, or pinned page by typing, such as "personal cal". ⌘D pins the current page under its account; a pin stays on that service's own Google address. Drag services and pins up or down to reorder them within their account, or right-click for Move Up, Move Down, and removal. The shortcut numbers follow the new order, and removed services return through Open Service or ⇧⌘T. Pins are saved in MailPort's preferences and include the page address, so a pinned Gmail search keeps its search text there.

Right-click an account header to edit its label and color or remove it. Besides the five preset colors, the editor offers the macOS color panel and an HTML color code field such as `#1A73E8`. Remove and Keep Sign-In leaves its website data on this Mac. Remove and Sign Out deletes MailPort's cookies and website data for that account. Neither changes your Google account, email, or calendar.

In the tab strip, drag any tab left or right over another tab to rearrange it. Each tab moves independently, including Mail and Calendar tabs for the same account. Reordering keeps the active page loaded and saves the new order for the next launch.

Every tab has an × close button and a Close Tab context-menu action. ⌘W closes the active tab; ⇧⌘T reopens the last closed tab. Closing a tab preserves its account sign-in. Open tabs are restored across app restarts, including an intentionally empty tab strip. Reopen services from Open Service in the sidebar or the + menu in the tab strip.

Shortcuts: ⌘1–9 select tabs in the order shown, and the first nine show their shortcut beside them unless you turn that off in Settings; ⇧⌘[ / ⇧⌘] switch tabs; ⌘R reloads; ⌘N composes; ⇧⌘A adds an account. External website links open in the system browser; Google service pages and sign-in navigation remain in the app. Popups are handled in the current tab.

## Current limits

Passkeys for Google are not supported by this preview: WebKit requires a matching associated domain or Apple's managed browser passkey entitlement, neither of which is configured here. Google's existing "Try another way" flow may offer another method already configured on the account. Account security settings should remain unchanged.

Version 0.2.1 adds an experimental WebKit compatibility identity. The system WebKit build is checked against a narrow set of known engine-family release baselines from Apple's Safari release notes. For known family 624 builds, the app adds conservative Version/Safari compatibility tokens while retaining MailPortPreview's identity. The normal WebKit-generated OS/engine tokens are left unchanged. Unknown engine families keep the ordinary app identity. This targets website version detection; it does not make MailPort officially supported by Google, add missing browser APIs, or enable passkeys. No warning is hidden with CSS or page scripts.

Calendar notifications require MailPort to remain running, signed in, and online, with desktop notifications and event reminders enabled in Google Calendar. They are not an independent scheduling service: quitting MailPort or sleeping the Mac can prevent reminders. Focus and screen-sharing settings can suppress banners. Dock unread badges and independent mail polling are not implemented; tab unread counts use the loaded Gmail pages. Browser-based OAuth for a native API client would not log Gmail's website into this WebKit store.

This preview supports native download and upload dialogs, browser navigation, JavaScript dialogs, and account/service tabs. It does not yet reproduce Mailplane's extension system or attachment tools.

## Build

With Xcode and Swift 6:

```sh
./scripts/build.sh --test
```

Set `MAILPORT_BUILD_DIR` to place build caches elsewhere. `MAILPORT_DIST_DIR` changes where the app is written, and `MAILPORT_SIGN_IDENTITY` signs with a named certificate instead of locally. Debug builds never open the real profile: they use `MailPortSecurityTest-securityqa` in Application Support, or the folder named by `MAILPORT_PREVIEW_DATA_DIR`. Release builds ignore that variable. WebKit stores remain isolated by the app bundle identifier and account UUID.

## Xcode

Open `MailPort.xcodeproj` and select the **MailPort** scheme. ⌘R runs **MailPort Dev** and ⌘U runs all the Swift tests. The project signs with an Apple Development certificate for team `WDCGJTU726`, so Xcode must be signed in to that team.

Debug builds use the bundle identifier `com.chriswilson.mailport.embedded.securityqa`, and the app also refuses to open the real profile in any debug build. Accounts, sign-ins, preferences, and the PIN lock are kept apart from your installed MailPort, so you will sign in again the first time. Both apps can run at once. The Release configuration uses the real identifier and your real profile, so do not switch the Run action to Release for testing.

`project.yml` is the source of `MailPort.xcodeproj`. After adding, removing, or renaming files, run `xcodegen generate` (install with `brew install xcodegen`). Published releases come from `scripts/release.sh`, not from Xcode.

## Releasing

`scripts/release.sh` runs the tests, signs and notarizes the app, packages a stapled disk image in `dist/release/`, tags the commit, and publishes a GitHub release. Versions must stay on `0.x.y`. With no version given, it adds one to the last number of the latest `v0.x.y` tag, unless `Resources/Info.plist` already has a higher version. Either way the build number goes up when the version changes.

One-time setup on the release Mac:

1. Create a **Developer ID Application** certificate in Xcode → Settings → Accounts → Manage Certificates. This needs a paid Apple Developer Program membership, and only the team's Account Holder can create one.
2. Create an app-specific password at [account.apple.com](https://account.apple.com), then save the notary credentials:

   ```sh
   xcrun notarytool store-credentials mailport-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
   ```

Commit your work on `main`, then run one of:

```sh
./scripts/release.sh --dry-run   # Build and package only; no Apple or GitHub steps
./scripts/release.sh             # Release the next patch version after the latest tag
./scripts/release.sh 0.7.0       # Release a specific version
```

A failed run before publishing restores `Resources/Info.plist` and changes nothing in git. `MAILPORT_SIGN_IDENTITY`, `MAILPORT_NOTARY_PROFILE`, and `MAILPORT_RELEASE_REPO` override the certificate, notary profile, and target repository.

Release downloads follow the repository's visibility, so people without access to a private repository cannot download them. Moving from a local build to a Developer ID build changes the app's signature: macOS may ask again for Keychain access, notifications, camera, and microphone. Later Developer ID releases keep the same signing identity.

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

Gemini is available in Open Service, Go To, and Navigate. It opens gemini.google.com/app as an in-app tab using that account’s existing website data store. Gemini tabs support closing, reopening, rearranging, and restoring across launches like other service tabs.

Validation: all 29 tests passed after adding Gemini. The Google Apps menu showed Gemini for the current account and all account submenus. Selecting it opened Google Gemini at gemini.google.com/app in the same app window with the existing selected-account sign-in. No prompt submission was needed for this check.

## Version 0.3.0

The single-window application is now the main MailPort project and builds as `dist/MailPort.app`. The old Chrome launcher has been retired. This organizational change does not remove the existing limitations listed above.


## Calendar notifications (version 0.4.0)

Select Turn On Reminders in the sidebar, or open MailPort → Notifications…, and choose Enable notifications. Allow alerts in macOS, then choose an account and Open Calendar settings. In Google Calendar, select General → Notification settings → Desktop notifications. Repeat for each account and check that the calendars/events you use have reminder rules. Send test reminder checks native Mac delivery; a real Google event is required to validate the complete reminder path.

When enabled, Calendar pages are kept alive for all saved accounts, including accounts whose Calendar tab is closed. Notifications identify the account; clicking one opens that account’s Calendar tab. Gmail web notifications are also bridged when its page is loaded and Gmail desktop notifications are enabled.

Only top-level HTTPS pages on calendar.google.com and mail.google.com can request this bridge. The bridge does not accept arbitrary navigation URLs. Google generates the notification content and timing; MailPort delivers it through macOS UserNotifications. No Calendar API credentials or server are required.

Validation: 31 Swift tests and 4 JavaScript bridge tests passed. Native UI checks enabled MailPort alerts, verified macOS desktop/sound permissions, and sent a test reminder that macOS recorded as delivered. LiveKit already used Desktop notifications; GMail and Yepher were switched from Alerts to Desktop notifications. A temporary Google Calendar event produced a native macOS notification, confirmed in MailPort and the system notification delivery log. The same event was moved forward and produced another native reminder while its Calendar tab was closed and a different account’s Gemini tab was active. All temporary test events were removed. Notification-click routing remains unverified.

Run the JavaScript tests separately with Node (development only):

```sh
node --test scripts/test-notification-bridge.cjs
```


## Tab activity (version 0.5.0)

Mail tabs show their unread inbox count, hide the badge at zero, and display 999+ for large counts. Open Mail tabs load in the background so their counts can update while another account or service is selected. These are unread counts, not total inbox message counts.

Calendar tabs show a green dot while a timed event is in progress. The dot clears at the event’s end, within the tab strip’s 15-second refresh interval. All-day and declined events are excluded. Each open Calendar tab has a background view of today using the same account session, so browsing another date does not change the indicator. These observer pages do not have the native notification bridge and cannot duplicate MailPort alerts.

The observers read Gmail’s inbox counter/title and Google Calendar’s accessible event labels. Only counts and event time ranges reach the native tab UI; message bodies and event titles are not retained or sent by the activity bridge. Observations expire after five minutes without an update. Sign-in, offline periods, or website layout changes can make an indicator unavailable. Calendar label parsing currently supports the English interface used on this Mac; it uses the displayed GMT offset when available, otherwise the Mac’s local time zone.

Validation: 34 Swift tests and 10 JavaScript tests pass, covering zero/unread counts, expiration, overlapping events, exact start/end boundaries, displayed time zones, overnight events, excluded all-day/declined entries, and malformed input. Live UI checks showed Yepher’s unread badge while another tab was active, a live increase from 1 to 2 unread messages, and a Calendar dot during a temporary event, including while browsing a different week. The dot cleared at the event end without needing a page reload; the temporary event was then deleted.

Development checks:

```sh
./scripts/build.sh --test
node --test scripts/test-tab-activity.cjs scripts/test-notification-bridge.cjs
```


## Colab and NotebookLM (version 0.5.1)

Colab and NotebookLM are available in Open Service, Go To, and Navigate. They open as normal in-app tabs using the selected account’s existing website data store, with closing, reopening, rearranging, and restoration across launches.

Colab opens https://colab.research.google.com/. NotebookLM opens https://notebook.google.com/, Google’s current destination for the former notebooklm.google.com address. The MailPort label remains NotebookLM for easy recognition; Google’s website may show the [Gemini Notebook name](https://workspaceupdates.googleblog.com/2026/07/notebooklm-now-gemini-notebook.html). Service access still depends on the account’s Google permissions.

Validation: all 34 Swift tests passed. Native UI checks confirmed both services in the current-account menu and all account submenus. Colab loaded with the existing account control, and NotebookLM loaded Google’s Gemini Notebook page inside MailPort. No notebook was created, uploaded, or executed for these checks.


## External links (version 0.5.2)

Links to other websites open in the system default browser instead of replacing the current MailPort page. The rule covers direct links, JavaScript-created popup requests, Google URL redirect wrappers, and server redirects, including links to Google products other than the current tab’s service. Gmail’s own navigation remains in the tab. Normal Google sign-in/SSO redirects, embedded frames, mailto account selection, and attachment downloads retain their app handling. Plain HTTP website links are handed to the system browser; MailPort continues to load only HTTPS pages internally.

Validation: all 39 Swift tests pass, including new regression cases for scripted external links, same-frame and new-window handling, Google redirect wrappers, other Google products, SSO, and attachment exceptions. In the live app, Gmail’s public Program Policies link opened Gmail Help in the Mac’s default Chrome browser while the MailPort inbox remained open. The temporary browser tab was closed after the check.


## PIN privacy lock (version 0.6.0)

Open MailPort → Settings… (⌘,) and select **Require a PIN after sleep**. Choose and confirm a six-digit PIN, acknowledge the local-data reset rule, and select Enable PIN lock. The feature is off by default. Once enabled, MailPort requires the PIN after Mac sleep/wake and when launching the app. **Lock MailPort** (⌃⌘L) also locks immediately. Turning the setting off requires the current PIN.

While locked, MailPort removes its account pages from the window and memory, pauses media, and suppresses MailPort notifications. Unlocking restores the saved workspace and sign-ins. Notification reminders can be missed while locked.

**Ten consecutive incorrect PIN submissions erase MailPort’s local accounts and saved Google sessions.** The reset clears its website cookies/storage/cache, account file, tab and app preferences, delivered/pending notifications, and saved window state. It then returns to an empty workspace with PIN protection off. A correct PIN resets the failure count; closing or restarting the app does not. Attempts to turn protection off share the same counter. Cleanup that is interrupted or fails keeps access locked and resumes on the next launch.

The reset does not delete your Google accounts, email, calendar events, or online files. It does not delete downloaded files outside MailPort, backups, snapshots, the system clipboard, or OS swap. This is an app privacy lock, not encryption or a forensic secure-erase guarantee; continue using the Mac login password and FileVault for device protection.

The PIN is never saved as plaintext. Its salted PBKDF2-HMAC-SHA256 verifier (200,000 rounds) and persistent failure counter are stored in the local Keychain. Verification and counter updates are serialized across running app copies. Missing or inaccessible security records leave the app locked. Locally signed updates can require renewed Keychain access.

Validation: all 55 Swift tests and 10 JavaScript tests pass. Disposable profiles and test Keychain records cover correct/incorrect PINs, persistent and concurrent failure counts, the tenth-attempt reset, cookie removal, interrupted cleanup, launch locking, sleep/wake notification handling, sleep during verification, and duplicate submissions. The native settings screen was checked with an empty test profile. These checks did not put the Mac to sleep or clear any real accounts, and PIN protection remains off for you to configure.
