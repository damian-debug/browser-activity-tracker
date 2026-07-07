import { useRef, useState } from "react";
import { validateBackup, type ImportMode } from "../../shared/backup";
import { exportAll, importBackup } from "../../storage/backup-repo";
import { todayDateString } from "../../shared/utils";

export function DataTab() {
  const [mode, setMode] = useState<ImportMode>("merge");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleDownload = async () => {
    const backup = await exportAll();
    const blob = new Blob([JSON.stringify(backup, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `activity-tracker-backup-${todayDateString()}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleFile = async (file: File) => {
    setError(null);
    setResult(null);

    let raw: unknown;
    try {
      raw = JSON.parse(await file.text());
    } catch {
      setError("That file is not valid JSON.");
      return;
    }

    const validation = validateBackup(raw);
    if (!validation.ok) {
      setError(validation.error);
      return;
    }

    if (
      mode === "replace" &&
      !confirm("Replace ALL current data (projects, tags, rules, sessions, settings) with this backup? This cannot be undone.")
    ) {
      return;
    }

    setBusy(true);
    try {
      const summary = await importBackup(validation.backup, mode);
      setResult(
        `Restored ${summary.projects} project${summary.projects !== 1 ? "s" : ""}, ` +
          `${summary.tags} tag${summary.tags !== 1 ? "s" : ""}, ` +
          `${summary.rules} rule${summary.rules !== 1 ? "s" : ""}, ` +
          `${summary.sessions} session${summary.sessions !== 1 ? "s" : ""}` +
          (summary.skipped > 0 ? ` (${summary.skipped} skipped — this device's copy is newer).` : ".")
      );
    } catch (e) {
      setError(`Import failed: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setBusy(false);
      // Allow re-selecting the same file
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  };

  return (
    <>
      <section className="options-section">
        <h2>Backup</h2>
        <p className="section-hint">
          Download a single file containing everything: projects, tags, rules, sessions, and
          settings. Keep it somewhere safe, or use it to move to another computer.
        </p>
        <button className="btn-add" onClick={handleDownload}>Download full backup</button>
      </section>

      <section className="options-section">
        <h2>Restore</h2>
        <p className="section-hint">
          Restore from a backup file created above.
        </p>

        <div className="field">
          <label className="checkbox-label">
            <input
              type="radio"
              name="import-mode"
              checked={mode === "merge"}
              onChange={() => setMode("merge")}
            />
            Merge — combine with this device's data (newer copy of each record wins)
          </label>
          <label className="checkbox-label">
            <input
              type="radio"
              name="import-mode"
              checked={mode === "replace"}
              onChange={() => setMode("replace")}
            />
            Replace — wipe this device's data first and restore the backup exactly
          </label>
        </div>

        <input
          ref={fileInputRef}
          type="file"
          accept=".json,application/json"
          disabled={busy}
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file) handleFile(file);
          }}
        />

        {busy && <p className="section-hint">Restoring…</p>}
        {result && <p className="save-success">{result}</p>}
        {error && <p className="form-error">{error}</p>}
      </section>
    </>
  );
}
