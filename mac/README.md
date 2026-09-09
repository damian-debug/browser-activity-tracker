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

## Using it

Click the menu bar timer for the popover: what is being tracked now, favourite
projects (click one to start a timer on it), today's totals, and the dashboard.
Right-click for pause and quit.

**Dashboard** (from the popover, or right-click → Open Dashboard):

| Tab | What it is for |
|---|---|
| Projects | Where the time went, billable split, session counts |
| Review Needed | Anything unassigned or attributed with low confidence |
| Sessions | Every session, with the project editable inline |
| Apps & Sites | Which apps and which sites, side by side |

**Review Needed is where the app gets better.** Correcting a suggestion tells
the model both that it was wrong and what the right answer was. When you are
sure, *Rule…* turns one decision into a standing rule and applies it to
matching past work in one go — suggestions are offered narrowest first, because
a broad rule quietly swallows unrelated time.

Export CSV covers the visible range. Backup saves everything (projects, tags,
rules, sessions, settings) to a single file; restore either merges it or
replaces what is here.

## How attribution works

In order, first match wins:

1. **A manual timer or override** — you said so.
2. **A rule you wrote** — deterministic, scored 60–95 by how specific it is.
3. **A learned suggestion** — from what you have assigned before, capped at 90
   so a rule always outranks it.
4. **Unassigned** — nothing was confident enough.

A learned suggestion below `learnedMinimumConfidence` (50) is discarded rather
than applied weakly; between that and `reviewConfidenceThreshold` (70) it is
applied but flagged for review; above, it is applied quietly. An unfilled gap
costs a moment of attention, a wrong invoice costs more.

The model learns only from decisions with real intent behind them — a manual
choice, a timer, a rule you wrote, or you confirming a suggestion. It never
learns from its own guesses: a model that treats its own output as evidence
converges on whatever it guessed first and grows more certain the longer it is
wrong.

## Data

Everything is local. There are no network calls anywhere in the app.

```
~/Library/Application Support/TimeTracker/tracker.sqlite
```

Import from the Chrome extension via its Backup & Restore export — the v3
format is read directly.
