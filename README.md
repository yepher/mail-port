# MailPort

MailPort puts Gmail, Calendar, and your other Google services in one Mac window, with every account a click away. Each account keeps its own sign-in, and pages stay loaded as you switch between them.

![MailPort with Work and Personal accounts in the sidebar](docs/screenshot.png)

MailPort is an independent preview, not affiliated with or endorsed by Google. It shows Google's own web pages, and Google may reject its embedded browser or ask for extra verification, so sign-in isn't guaranteed for every account.

## Install

MailPort needs macOS 14 or later on Apple silicon.

1. Download the latest `.dmg` from [Releases](https://github.com/yepher/mail-port/releases/latest).
2. Open it and drag MailPort to Applications.

MailPort then keeps itself up to date. If your copy is version 0.6.1 or earlier, repeat these steps once to get the version that can.

## Using MailPort

### Add an account

1. Select **Add Account** at the bottom of the sidebar.
2. Enter a name such as Work, then choose a color. The email label is optional and only used for display.
3. Sign in on Google's page in the account's Mail view.

The name and color are labels only. The Google account is whichever one you sign in to. Passkeys aren't supported, so use **Try another way** on Google's page if it offers one.

### Move around

- **Switch views:** select a service in the sidebar, or press ⌘1–9. The first nine views show their shortcut.
- **Go To:** press ⌘T and type, such as `personal cal`, to find any account, service, or pinned page.
- **Open a service:** select **Open Service** under an account. Mail, Calendar, Drive, Contacts, Chat, Meet, Gemini, Colab, and NotebookLM are available.
- **Check where you are:** the toolbar shows the current account, its email label, and the page's address.

Links to other websites open in your default browser. Unread counts appear beside Mail, and a green dot beside Calendar means a timed event is happening now.

### Organize the sidebar

- **Reorder:** drag a service or pin up or down within its account, or right-click it for **Move Up** and **Move Down**. Shortcut numbers follow the new order.
- **Remove a service:** right-click it and choose **Remove from Sidebar**, or press ⌘W. You stay signed in. Press ⇧⌘T or use **Open Service** to bring it back.
- **Collapse an account:** select its header.
- **Hide the sidebar:** press ⌃⌘S.
- **Use tabs instead:** choose View > Use Tab Bar.
- **Hide shortcut numbers:** turn off **Show keyboard shortcuts next to views** in Settings.

### Pin pages

Go to a page, such as a Gmail search or Drive folder, then press ⌘D or select the pin button in the toolbar. Give it a name, and it appears under that account. To remove a pin, right-click it.

Pins work on each service's main Google address. They're stored on your Mac and include the page address, so a pinned Gmail search keeps its search words there.

### Change or remove an account

Right-click an account's header.

- **Edit** changes its name, email label, and color. Pick a preset, use the color panel, or enter an HTML code such as `#1A73E8`.
- **Remove** offers two choices. **Remove and Keep Sign-In** leaves its website data on your Mac. **Remove and Sign Out** deletes MailPort's cookies and website data for that account.

Neither choice changes your Google account, email, or calendar.

### Turn on Calendar reminders

1. Select **Turn On Reminders** in the sidebar, or choose MailPort > Notifications.
2. Choose **Enable notifications** and allow alerts in macOS.
3. Choose an account and open its Calendar settings.
4. In Google Calendar, go to General > Notification settings and select **Desktop notifications**.
5. Repeat steps 3 and 4 for each account.

MailPort must be running, online, and signed in for reminders to arrive. They can be missed while the app is quit, locked, or your Mac is asleep. Clicking a Calendar reminder opens that account's Calendar. Gmail notifications also appear when they're enabled in Gmail and its page is loaded.

### Lock MailPort with a PIN

PIN lock is off by default. To turn it on, open Settings (⌘,), select **Require a PIN after sleep**, and choose a six-digit PIN. MailPort then asks for the PIN when it launches and after your Mac sleeps. Press ⌃⌘L to lock it right away.

> [!WARNING]
> Ten incorrect PIN entries in a row erase MailPort's accounts, saved Google sign-ins, and settings on this Mac. Restarting the app doesn't reset the count. Your Google accounts, email, and calendars aren't affected, and neither are files you've downloaded.

The lock keeps people out of the app. It isn't encryption, so keep using your Mac login password and FileVault.

### Update MailPort

MailPort checks for new versions automatically and asks before installing one. Your accounts and sign-ins are kept. To check now, choose MailPort > Check for Updates. To stop automatic checks, turn off **Check for updates automatically** in Settings.

### Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Go to an account, service, or pin | ⌘T |
| Switch to view 1–9 | ⌘1–⌘9 |
| Next or previous view | ⇧⌘] or ⇧⌘[ |
| New email | ⌘N |
| Pin the current page | ⌘D |
| Reload | ⌘R |
| Return to the service's home page | ⇧⌘H |
| Close the current view | ⌘W |
| Reopen the last closed view | ⇧⌘T |
| Add an account | ⇧⌘A |
| Show or hide the sidebar | ⌃⌘S |
| Settings | ⌘, |
| Lock MailPort | ⌃⌘L |

## Privacy

MailPort has no server and doesn't use a Google API. Its only other connection is the update check, which reads the latest release from GitHub. Sign-ins are handled by Google's own pages and stored locally by WebKit, with each account kept separate. Unread counts and Calendar dots read only counts and event times, not message contents or event titles.

## Current limits

- Passkeys don't work.
- Unread counts come from loaded Mail pages, and there's no Dock badge. They can disappear while you're signed out or offline.
- Calendar dots need Google Calendar in English.
- Browser extensions and attachment tools aren't included.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for build, test, and release instructions.
