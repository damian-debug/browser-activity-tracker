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
npm test          # Vitest — expect 5 test files / 49 tests passing
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
  `tracker.ts` wires up Chrome event listeners and holds the readiness gate
  (`ensureReady`) so no event can race the restore.
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
  from what used to be `projectId`/`projectName`, and start `Unassigned`).
  **Important gotcha already fixed once:** IndexedDB cannot index booleans —
  `syncedToSheets` is stored as `0|1`, not `boolean`, specifically so
  `where("syncedToSheets").equals(0)` works.
- `src/popup/`, `src/options/`, `src/dashboard/` — React UIs. Options has tabs
  for General/Projects/Tags/Sync. Dashboard has Projects/Review
  Needed/Sessions/Domains tabs, plus session edit and split modals.
- `src/sync/sheets-sync.ts` + `apps-script/Code.gs` — Google Sheets export via
  an Apps Script webhook (no OAuth). `Code.gs` upserts by Session ID into a
  "Sessions v2" tab, so edited/re-synced sessions update in place.

## Conventions / things learned the hard way

- Never trust "the DevTools console is open" as a neutral observation state —
  focusing the service-worker inspector blurs the tracked tab and pauses
  tracking. Verify live tracking via the popup instead.
- When adding a new rule type or parser, add engine/parser tests in
  `tests/rule-engine.test.ts` — the engine is pure and deterministic by design,
  so it's cheap to test exhaustively.
- Don't index boolean fields in Dexie schemas (see gotcha above).
