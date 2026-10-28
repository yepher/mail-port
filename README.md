# MailPort

A personal macOS workspace for Gmail and Google Calendar, with shortcuts to the rest of your Google apps. This is an early working prototype for replacing part of a Mailplane workflow.

MailPort is a native Swift Mac app. It opens Google services in dedicated Google Chrome app-mode windows, keeping Google's complete web interfaces and browser-managed sign-in. Each account gets a separate Chrome profile. Chrome is required and should be kept updated.

## Run

Open `dist/MailPort.app`. Add an account label, then open Gmail and sign in directly to Google in its browser window. Use that same account's Calendar or other shortcuts to share the session. An account label is only for navigation; adding one does not authenticate an account.

You can move the app to your Applications folder. This build is signed locally with an ad hoc signature, suitable for use on this Mac; it is not notarized for public distribution. It runs natively on Apple silicon and requires macOS 14 or later. It does not need Rosetta.

MailPort registers support for `mailto:` links, but does not change your default email app automatically. Select it as your default email reader in Apple Mail's General settings if desired.

Workspace shortcuts work while MailPort is active:

| Shortcut | Action |
| --- | --- |
| ⌘N | New message |
| ⇧⌘A | Add account |
| ⇧⌘O | Open Gmail and Calendar |
| ⌘1 through ⌘6 | Open Gmail, Calendar, Drive, Contacts, Chat, or Meet |
| ⌥⌘[ / ⌥⌘] | Previous / next account |
| ⌘0 | Show the MailPort workspace |
| ⌘, | Notification setup |

The menu bar icon also opens account shortcuts when the workspace is closed.

## Build

Requires Xcode or Apple's command-line developer tools, with Swift 6 or newer.

```sh
./scripts/build.sh --test
```

The script runs tests, builds a release executable for the current Mac's architecture, generates an original icon, creates `dist/MailPort.app`, and signs the bundle locally. Omit `--test` to build without running tests. Build caches stay inside `.build`. The icon generator provides native ICNS packaging when Apple's `iconutil` cannot run in a restricted build environment.

## Data

MailPort stores its files in `~/Library/Application Support/MailPort/`:

- `accounts.json` contains account IDs, labels, optional email addresses, and colors. The selected account ID is stored in macOS preferences.
- `BrowserProfiles/<account UUID>/` contains that account's browser session, cookies, site storage, and other Chrome profile data.

Sign-in happens on Google's pages. MailPort does not ask for your password, export credentials, or copy existing Mailplane or Chrome cookies. Treat profile folders as private account data. For isolated app testing, set `MAILPORT_DATA_DIR` to a separate directory before launching the executable.

Removing an account shortcut preserves its browser session. Sign out in the corresponding Google window before removing its shortcut if you want that session to end.

## Current limits

Service windows are owned by Chrome and open separately from the native workspace. This prototype does not provide embedded service tabs, Mailplane's extension integrations, an unread badge, native quick replies, or automatic migration of existing sessions. Website notifications are handled by Google and Chrome and depend on site and macOS permission settings; MailPort does not guarantee notifications. Signing in and everyday mail/calendar use still need validation with your own accounts.

Google blocks OAuth sign-in in embedded webviews. Running the installed browser avoids making a promise that an embedded Gmail view can support. A future fully native mail client would need Google API authorization and substantially more mail/calendar functionality.

References: [Google's secure browser policy](https://developers.google.com/identity/protocols/oauth2/policies), [Chromium's profile directory documentation](https://github.com/chromium/chromium/blob/main/docs/user_data_dir.md), and [Chrome web apps](https://support.google.com/chrome/answer/9658361).
