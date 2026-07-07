/**
 * Browser Activity Tracker — Google Apps Script Webhook (V2)
 *
 * Writes to a "Sessions v2" tab and UPSERTS by Session ID: re-synced sessions
 * (edited or split in the extension) update their existing row instead of
 * creating a duplicate. Existing V1 "Sessions" tabs are left untouched.
 *
 * Setup:
 *   1. Open your Google Sheet → Extensions > Apps Script
 *   2. Paste this file, replacing all existing content
 *   3. Click Deploy > New deployment > Web app
 *      - Execute as: Me
 *      - Who has access: Anyone (or Anyone with Google account for more security)
 *   4. Copy the deployment URL into the extension's Settings → Sheets Sync
 *
 * NOTE: if you are upgrading from V1, you MUST create a NEW deployment
 * (Deploy > New deployment) — editing the code alone does not update the
 * already-deployed web app, and the URL changes with the new deployment.
 */

const SHEET_NAME = "Sessions v2";

const HEADERS = [
  "Date",
  "Start Time",
  "End Time",
  "Duration (min)",
  "Project",
  "Client",
  "Tags",
  "Billable",
  "Reviewed",
  "Assignment Source",
  "Assignment Confidence",
  "Domain",
  "Service",
  "Detected Entity ID",
  "Detected Entity Name",
  "Page Title",
  "URL",
  "Notes",
  "Session ID",
];

// Session ID column index (1-based) — used for the upsert lookup.
const ID_COLUMN = HEADERS.length;

function getOrCreateSheet() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(SHEET_NAME);
  if (!sheet) {
    sheet = ss.insertSheet(SHEET_NAME);
    sheet.appendRow(HEADERS);
    sheet.setFrozenRows(1);
    const headerRange = sheet.getRange(1, 1, 1, HEADERS.length);
    headerRange.setFontWeight("bold");
    headerRange.setBackground("#4a86e8");
    headerRange.setFontColor("#ffffff");
  }
  return sheet;
}

function sessionToRow(s) {
  const tz = Session.getScriptTimeZone();
  const start = new Date(s.startTime);
  const end = new Date(s.endTime);
  return [
    Utilities.formatDate(start, tz, "yyyy-MM-dd"),
    Utilities.formatDate(start, tz, "HH:mm:ss"),
    Utilities.formatDate(end, tz, "HH:mm:ss"),
    (s.durationSeconds / 60).toFixed(2),
    s.project || "Unassigned",
    s.client || "",
    s.tags || "",
    s.billable ? "Yes" : "No",
    s.reviewed ? "Yes" : "No",
    s.assignmentSource || "",
    s.assignmentConfidence != null ? s.assignmentConfidence : "",
    s.domain || "",
    s.service || "",
    s.detectedEntityId || "",
    s.detectedEntityName || "",
    s.title || "",
    s.url || "",
    s.notes || "",
    s.id || "",
  ];
}

function doPost(e) {
  // Serialize concurrent syncs so two requests can't both append the same ID.
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    const data = JSON.parse(e.postData.contents);
    const sessions = data.sessions;

    if (!sessions || !Array.isArray(sessions) || sessions.length === 0) {
      return jsonResponse({ ok: false, error: "No sessions provided" });
    }

    const sheet = getOrCreateSheet();

    // Build Session ID → row number map from the existing sheet.
    const lastRow = sheet.getLastRow();
    const idToRow = {};
    if (lastRow > 1) {
      const ids = sheet.getRange(2, ID_COLUMN, lastRow - 1, 1).getValues();
      for (let i = 0; i < ids.length; i++) {
        const id = String(ids[i][0]);
        if (id) idToRow[id] = i + 2; // sheet rows are 1-based; +1 for header
      }
    }

    let updated = 0;
    const toAppend = [];

    for (const s of sessions) {
      const row = sessionToRow(s);
      const existingRow = s.id ? idToRow[s.id] : undefined;
      if (existingRow) {
        sheet.getRange(existingRow, 1, 1, HEADERS.length).setValues([row]);
        updated++;
      } else {
        toAppend.push(row);
      }
    }

    if (toAppend.length > 0) {
      sheet
        .getRange(sheet.getLastRow() + 1, 1, toAppend.length, HEADERS.length)
        .setValues(toAppend);
    }

    return jsonResponse({ ok: true, inserted: toAppend.length, updated: updated });
  } catch (err) {
    return jsonResponse({ ok: false, error: err.toString() });
  } finally {
    lock.releaseLock();
  }
}

// GET handler for the extension's "Test" button.
function doGet() {
  return jsonResponse({ ok: true, message: "Browser Activity Tracker webhook v2 is live" });
}

function jsonResponse(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(
    ContentService.MimeType.JSON
  );
}
