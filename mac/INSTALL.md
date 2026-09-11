# Installing Activity Tracker

## For the team

Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/damian-debug/browser-activity-tracker/master/mac/scripts/install.sh | bash
```

That downloads the latest release, checks its signature, installs it to
`/Applications`, and starts it. A timer appears in your menu bar.

Run the exact same command again to update — your tracked history, projects,
rules and permissions all survive.

Works on Apple Silicon and Intel, macOS 14 and later.

### Can't see the timer in the menu bar?

It is almost certainly running — macOS just has nowhere to put the icon. When
the menu bar is full, macOS hides new icons without saying so, and on a MacBook
with a notch there is not much room to begin with. The newest app's icon is the
first to go.

Activity Tracker checks where its icon actually landed. If it is hidden, the
app opens its own window with everything the menu bar would have shown, and
you can bring that window back at any time by **opening Activity Tracker from
Spotlight** (⌘-Space, type "Activity").

To get the icon back:

- **System Settings → Menu Bar → Allow in the Menu Bar**: switch off an app or
  two you don't need up there — and check Activity Tracker is switched on.
- Or quit a menu bar app you're not using.
- On an external display the menu bar has much more room; the icon usually
  shows there even when it doesn't on the laptop screen.

For support, this shows where macOS put the icon each time the app started
(`visible`, `behindNotch` or `offScreen`) — only the icon's position, nothing
about what is being tracked:

```bash
/usr/bin/log show --last 1d --style compact --predicate 'subsystem == "studio.goodspeed.timetracker"'
```

(The full path matters: in zsh, a bare `log` is a different, built-in command.)

### After installing

The app asks for **Accessibility** permission
(System Settings → Privacy & Security → Accessibility).

You can say no and it still works — it will see *which app* you are in, and
that is all. Granting it lets the app read window titles and open file paths,
which is what lets it tell "Acme" work apart from "Beta Corp" work inside the
same editor or the same Slack. If you use a browser, it will separately ask for
permission to read the address of the current page, per browser.

### What this does with your data

Everything stays in a database on your own Mac. The app makes no network
requests of any kind — there is no account, no server, and nobody else can see
your activity. If you want to share hours with someone, you export the rows you
choose, yourself, from the dashboard.

### Uninstalling

```bash
curl -fsSL https://raw.githubusercontent.com/damian-debug/browser-activity-tracker/master/mac/scripts/uninstall.sh | bash
```

This removes the app, its "Open at login" entry, its Accessibility and
browser permissions, and its preferences. It then asks whether to delete your
tracked history as well — **the default is to keep it**, so reinstalling picks
up where you left off. If you do delete it, it goes to the Trash rather than
being erased, so a mistaken "y" is recoverable until you empty the Trash.

To skip the question, add a flag:

```bash
curl -fsSL https://raw.githubusercontent.com/damian-debug/browser-activity-tracker/master/mac/scripts/uninstall.sh | bash -s -- --delete-data
curl -fsSL https://raw.githubusercontent.com/damian-debug/browser-activity-tracker/master/mac/scripts/uninstall.sh | bash -s -- --keep-data
```

Want a copy of your hours first? Export them from the dashboard before
uninstalling.

Dragging the app to the Trash also works, but leaves things behind: macOS keeps
the login item registered and enabled after its app is deleted, and the
permission entries stay listed in System Settings. The script cleans those up
in the one order that works — the login item can only be removed by the app
itself, and permissions can only be reset while the app still exists.

If you installed 1.0.0 and turned on "Open at login", the script cannot
remove that entry for you (the hook it uses arrived in 1.0.1). It will say so;
switch Activity Tracker off in System Settings → General → Login Items.

---

## Why the Terminal command

macOS flags anything downloaded by a browser, Slack, Mail or AirDrop with
`com.apple.quarantine`. Gatekeeper then refuses to open apps that lack an Apple
Developer ID, and since macOS 15 the old right-click → Open shortcut is gone —
you have to go into System Settings and click past a malware warning.

`curl` does not set that flag, so the Terminal route is both fewer steps and
less alarming than a download link would be. We are skipping Apple's
notarization, not the integrity check: `install.sh` verifies the code signature
and pins the exact certificate the build was signed with, so a substituted or
tampered build is refused.

If you would rather read the script before running it, it is
[scripts/install.sh](scripts/install.sh) — drop the `| bash` to just print it.

### What we give up by not notarizing

- The app cannot be installed by double-clicking a downloaded zip without
  Gatekeeper warnings. The install command exists precisely to avoid that.
- No automatic updates. Re-running the install command is the update
  mechanism, deliberately: an update checker would mean the app phoning home,
  and "no network calls, ever" is a property worth more than convenience here.
- If this is ever distributed outside the team, notarization becomes
  worthwhile — an organization Apple Developer account, $99/yr, and a D-U-N-S
  number that takes a week or two to come through.

---

## Cutting a release (maintainer)

```bash
cd mac
./make-release.sh 1.0.1
gh release create v1.0.1 dist/ActivityTracker.zip \
  --title "Activity Tracker 1.0.1" --notes "What changed"
```

`make-release.sh` builds universal, signs, and refuses to package unless the
signature matches the pinned certificate — because every teammate's
Accessibility grant is keyed to that exact signature. Sign a release with a
different identity and everyone silently loses permission, while System
Settings still shows the app as allowed.

The install command never changes: it always resolves to the newest release.

### If the signing identity is ever lost or rotated

The pinned hash lives in two places that must move together —
`EXPECTED_CERT_SHA1` in `make-release.sh` and in `scripts/install.sh`
(the build asserts they match). Rotating it means everyone re-grants
Accessibility once, so keep the certificate backed up:

```bash
security export -k login.keychain -t identities -f pkcs12 -o timetracker-signing.p12
```

Store that somewhere safe. Without it, a rebuild cannot produce a signature
the team's existing grants recognise.
