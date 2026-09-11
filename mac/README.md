# Activity Tracker (macOS)

Native menu bar time tracker. Replaces the Chrome extension in `../extension`,
which could only see browser tabs.

Installing it on a teammate's Mac: see [INSTALL.md](INSTALL.md).

## Layout

| Path | What it is |
|---|---|
| `TimeTrackerCore/` | Pure domain logic — models, rule engine, timing, aggregation, backup. No AppKit, no dependencies, runs under `swift test` |
| `TimeTrackerApp/` | The app — sensing, GRDB store, menu bar UI |
| `make-app.sh` | Assembles `build/Activity Tracker.app` |
| `make-release.sh` | Packages a signed universal build for the team |
| `scripts/install.sh` | What teammates run to install and update |
| `scripts/uninstall.sh` | Removes the app, login item, permissions and preferences; asks about data |
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
| Automation | Browser tab URLs, and with them Figma file / Framer project / Bubble app detection | Automation, per browser |

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
sure, *Rule…* turns one decision into a standing rule.

A rule is a list of conditions that must **all** hold, which is what makes
shared tools workable: Slack is not a project, but *Slack and a title
containing `acme-internal`* is. Add conditions with **Add condition** in the
editor; each one narrows what can match, so a compound rule is also scored
more confidently than either half alone.

Rules can target a project *or* a project and a feature, and the suggested
match is a starting point rather than a fixed choice — the type and value are
both editable, because the app can see what you did but only you know how far
it should generalise. Before saving, it says how many stored sessions the rule
would claim, and warns when it also reaches work you have already decided,
which is usually the sign of a rule broader than intended.

The **Rules** tab lists everything created so far, grouped by project. Rules
can be edited, disabled, deleted, or applied to work recorded before they
existed. Disabling or deleting a rule never unpicks time it already assigned:
that was a decision, and reversing it silently would be worse than leaving it.

Export CSV covers the visible range. Backup saves everything (projects, tags,
rules, sessions, settings) to a single file; restore either merges it or
replaces what is here.

## Projects and features

A feature is a project with a parent — two levels, no deeper. `Acme Corp ›
Payment integration`. Sessions record both, so project totals stay whole
however finely the work is broken down, and every existing report, rule and
export keeps working untouched.

Pick the feature from the popover next to the project. It is deliberately
**persistent**: it stays set until you change it, and applies only while its
own project is the one being tracked. You know which feature you are on; the
Mac does not.

Four signals help it learn which feature is which. None of them *are*
features — they are evidence fed to the same learning layer as everything
else, so picking "Payments" once while on `feature/payments` is what creates
the association:

| Signal | Where it comes from |
|---|---|
| Ticket key | `ACME-123` in a URL or window title (Jira, Linear), or `repo#482` for GitHub issues and PRs |
| Git branch | `.git/HEAD` beside the open document. Ignores main/master/develop, which name no feature |
| Figma page | The `node-id` in a Figma URL, so one page of a file is distinguishable from another |
| Framer screen | The `node` in a Framer editor URL, or the page path of a `*.framer.app` site |

Figma and Framer tabs are titled after the file, never the screen, so while
one is in front the browser's address is re-read every 4 seconds rather than
only on title changes. Moving to a screen that a rule or the learned model
puts on a different feature starts a new session; clicking anything nothing
is known about stays in the current one, so a project visit does not
fragment. The quickest way to teach screens is to pick the feature in the
popover as you move between them.

Git branch needs a document path, which Electron editors like VS Code do not
expose — it works for Xcode and native editors today.

### Electron apps

Apps like Claude report a window title of just their own name, so every
conversation looks like the same work. They are Chromium underneath, and
Chromium exposes a web area with a real URL — but only after a client asks for
the full accessibility tree via `AXManualAccessibility`.

Two costs, so this is opt-in per app rather than done to anything that might
be Electron (`WebAppReader.supported`):

- Asking makes the target app build and maintain its whole accessibility
  tree, which is real work for it.
- That tree contains everything visible on screen. The reader takes the URL
  and a title and nothing else; conversation content is never read.

Claude conversations then become first-class entities, so each one can be
assigned and learned separately, and navigating within one stays a single
session.

To see what any app exposes:

```bash
touch ~/Library/Application\ Support/TimeTracker/DEBUG_AX
# relaunch, then read ax-<bundle-id>.txt in the same folder
```

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
