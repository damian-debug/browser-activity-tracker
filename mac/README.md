# Activity Tracker (macOS)

Native menu bar time tracker. Replaces the Chrome extension in `../extension`,
which could only see browser tabs.

## Layout

| Path | What it is |
|---|---|
| `TimeTrackerCore/` | Pure domain logic — models, rule engine, timing, aggregation, backup. No AppKit, no dependencies, runs under `swift test` |
| `TimeTrackerApp/` | The app — sensing, GRDB store, menu bar UI |
| `make-app.sh` | Assembles `build/Activity Tracker.app` |
| `scripts/create-signing-identity.sh` | One-time setup for a stable signing identity |

## Build and run

```bash
cd mac
./make-app.sh              # debug
./make-app.sh release      # release
open "build/Activity Tracker.app"
```

Tests:

```bash
(cd TimeTrackerCore && swift test)
(cd TimeTrackerApp && swift test)
```

Xcode can open either `Package.swift` directly. There is deliberately no
`.xcodeproj`: the bundle is assembled by a script so the whole build stays
reviewable as plain text.

## Signing (do this once)

```bash
./scripts/create-signing-identity.sh
```

macOS keys the Accessibility permission to the app's **code signature**. Ad-hoc
signing changes that signature on every build, so the grant is silently dropped
— System Settings still lists the app as allowed while `AXIsProcessTrusted()`
returns false. A stable self-signed identity avoids the whole problem.

No password required, and no system trust store involved. The certificate does
need **both** `keyUsage=digitalSignature` and `extendedKeyUsage=codeSigning`:
with only the latter, `security find-identity` cheerfully lists the identity as
valid while `codesign` refuses it with "no identity found", which is a
thoroughly misleading way to spend an afternoon.

Without a stable identity the build still works; you just re-grant Accessibility
after each rebuild.

## Permissions

The app is designed to be useful at every level, and asks for nothing up front.

| Level | Unlocks | Permission |
|---|---|---|
| Default | Which app, for how long. Idle and lock detection. Manual timers | **None** |
| Accessibility | Window titles and open document paths — per-project attribution *inside* one app | Accessibility |
| Automation | Browser tab URLs, and with them Figma file / Bubble app detection | Automation, per browser |

Grant these from the app's popover, which only asks once a level is actually
missing.

Notes:
- **Accessibility, not Screen Recording.** `CGWindowListCopyWindowInfo` omits
  window titles without Screen Recording, and since macOS 15 that permission
  re-prompts every month, forever. Accessibility is granted once and also
  exposes the open document path.
- **Firefox** ships no usable AppleScript dictionary, so it degrades to
  app-level tracking.
- The Mac App Store is not a viable target: sandboxed apps cannot use the
  Accessibility API against other apps, and Apple Events exceptions are
  routinely rejected. Direct distribution is the only path for the full
  feature set — which is what every comparable tracker does.

## Data

Everything is local. There are no network calls anywhere in the app.

```
~/Library/Application Support/TimeTracker/tracker.sqlite
```

Import from the Chrome extension via its Backup & Restore export — the v3
format is read directly.
