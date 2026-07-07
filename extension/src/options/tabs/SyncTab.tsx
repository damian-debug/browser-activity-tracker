import { useState } from "react";
import type { AppSettings } from "../../shared/types";

interface Props {
  settings: AppSettings;
  onChange: (updated: AppSettings) => void;
}

export function SyncTab({ settings, onChange }: Props) {
  const [webhookStatus, setWebhookStatus] = useState<"idle" | "testing" | "ok" | "error">("idle");

  const updateSync = (patch: Partial<AppSettings["sync"]>) => {
    onChange({ ...settings, sync: { ...settings.sync, ...patch } });
  };

  const testWebhook = async () => {
    const url = settings.sync.sheetsWebhookUrl;
    if (!url) return;
    setWebhookStatus("testing");
    try {
      const res = await fetch(url, { method: "GET" });
      setWebhookStatus(res.ok ? "ok" : "error");
    } catch {
      setWebhookStatus("error");
    }
    setTimeout(() => setWebhookStatus("idle"), 4000);
  };

  return (
    <section className="options-section">
      <h2>Google Sheets Sync</h2>
      <div className="setup-steps">
        <p className="setup-step"><strong>1.</strong> Create a new Google Sheet (or reuse your existing one).</p>
        <p className="setup-step"><strong>2.</strong> Go to <strong>Extensions › Apps Script</strong>.</p>
        <p className="setup-step"><strong>3.</strong> Paste the contents of <code>apps-script/Code.gs</code> from this extension's source (V2 — writes to a "Sessions v2" tab).</p>
        <p className="setup-step"><strong>4.</strong> Click <strong>Deploy › New deployment › Web app</strong>. Set "Execute as: Me" and "Who has access: Anyone".</p>
        <p className="setup-step"><strong>5.</strong> Copy the deployment URL and paste it below. If upgrading from V1, you must create a <strong>new deployment</strong> — the URL changes.</p>
      </div>

      <div className="field">
        <label>Webhook URL</label>
        <div className="webhook-row">
          <input
            type="url"
            placeholder="https://script.google.com/macros/s/..."
            value={settings.sync.sheetsWebhookUrl}
            onChange={(e) => updateSync({ sheetsWebhookUrl: e.target.value })}
          />
          <button
            className={`btn-test ${webhookStatus}`}
            onClick={testWebhook}
            disabled={!settings.sync.sheetsWebhookUrl || webhookStatus === "testing"}
          >
            {webhookStatus === "testing" ? "Testing…" : webhookStatus === "ok" ? "Connected ✓" : webhookStatus === "error" ? "Failed ✗" : "Test"}
          </button>
        </div>
      </div>

      <div className="field">
        <label className="checkbox-label">
          <input
            type="checkbox"
            checked={settings.sync.autoSyncEnabled}
            onChange={(e) => updateSync({ autoSyncEnabled: e.target.checked })}
          />
          Auto-sync periodically
        </label>
      </div>

      {settings.sync.autoSyncEnabled && (
        <div className="field">
          <label>Sync interval (minutes)</label>
          <input
            type="number"
            min={5}
            max={1440}
            value={settings.sync.syncIntervalMinutes}
            onChange={(e) => {
              const n = parseInt(e.target.value, 10);
              if (!isNaN(n) && n >= 5) updateSync({ syncIntervalMinutes: n });
            }}
          />
        </div>
      )}
    </section>
  );
}
