# Browser Activity Tracker

A Manifest V3 Chrome extension that automatically tracks active browser time and
attributes it to user-defined **projects**, so time doesn't need to be logged
manually in a CRM/HR tool. Full background and rationale: see
`Browser Activity Tracker - Handoff Document.docx` at the project root.

All code lives under `extension/`.

## Build & test

```bash
cd extension
npm install
npm test          # Vitest — expect 10 test files / 73 tests passing
npm run typecheck  # tsc --noEmit
npm run build      # outputs extension/dist/
```

Load the extension: `chrome://extensions` → enable Developer mode → **Load
unpacked** → select `extension/dist`. After any source change: `npm run build`,
then click the refresh icon on the extension card.

Node ≥20 required (this project was developed on Node 24 — see `.nvmrc`).

## Architecture

**Core mental model:** parsers detect *what* a page is (a Figma file, a Bubble
app — `detectedEntityId`/`detectedEntityName`); rules decide *whose* time it is
(`projectId`). Manual assignment always overrides automatic rules.

- `src/background/` — MV3 service worker. `session-manager.ts` is a state
  machine (start/pause/resume/end) that persists every mutation to
  `chrome.storage.local` so an in-flight session survives the SW being killed
  and restarted (~30s idle timeout is normal in MV3). `restoreState()` decides
  whether to credit or discard the gap on wake, based on `MAX_CREDIT_GAP_SECONDS`.
  `tracker.ts` wires up Chrome event listeners, holds the readiness gate
  (`ensureReady`) so no event can race the restore, and serializes all
  session-mutating handlers through `enqueue` (Chrome fires several events per
  user action; two interleaved reconciles would fragment sessions). Window
  focus gain must `reconcile()` — `tabs.onActivated` does NOT fire when
  switching between Chrome windows. Timed overrides are enforced by a one-shot
  `OVERRIDE_EXPIRY` alarm, re-derived from storage on every bootstrap.
- `src/parsers/` — URL → entity extraction (Figma file ID, Bubble app ID).
  Continuity across navigation within the same entity is handled by
  `src/shared/tracking-target.ts` (`isSameTarget`), so clicking around inside
  one Bubble app or Figma file doesn't fragment into many tiny sessions.
- `src/attribution/` — the V2 rule engine. `rule-engine.ts` matches
  `ProjectRule`s (domain/URL/path/query-param/title/regex) with priority +
  specificity tie-breaking; `assign-session.ts` layers active-project overrides
  on top; `confidence.ts` holds the scoring table; `create-rule-from-session.ts`
  generates rule suggestions for the "create rule from this session" UX.
- `src/storage/` — Dexie (IndexedDB) repos. `db.ts` has the v1→v2 schema
  migration (old sessions get `detectedEntityId`/`detectedEntityName` populated
  from what used to be `projectId`/`projectName`, and start `Unassigned`) and
  the v2→v3 migration (drops the Sheets-sync `syncedToSheets` field/index).
  `backup-repo.ts` does full export/import against `src/shared/backup.ts`.
- `src/popup/`, `src/options/`, `src/dashboard/` — React UIs. Options has tabs
  for General/Projects/Tags/Backup & Restore. Dashboard has Projects/Review
  Needed/Sessions/Domains tabs, session edit and split modals, and CSV/JSON
  export of the visible date range.
- **No network calls anywhere** — the extension is fully local by design (a
  Google Sheets webhook sync existed pre-2.1 and was removed for Web Store
  publication). Data portability is via `src/shared/backup.ts` (pure
  build/validate/merge logic) and `src/shared/csv.ts`. Keep it that way: new
  features must not add remote requests or host permissions.

## Conventions / things learned the hard way

- Never trust "the DevTools console is open" as a neutral observation state —
  focusing the service-worker inspector blurs the tracked tab and pauses
  tracking. Verify live tracking via the popup instead.
- When adding a new rule type or parser, add engine/parser tests in
  `tests/rule-engine.test.ts` — the engine is pure and deterministic by design,
  so it's cheap to test exhaustively.
- Don't index boolean fields in Dexie schemas — IndexedDB cannot index
  booleans (bit us once with a `synced` flag; store `0|1` if you must query it).
- Derive date strings in LOCAL time (`src/shared/utils.ts`), never via
  `toISOString()` — `startOfDayMs`/`endOfDayMs` interpret them locally, so a
  UTC-derived "today" is wrong for part of every day in non-UTC timezones.
