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
