import { useState } from "react";
import type { AppSettings } from "../../shared/types";

interface Props {
  settings: AppSettings;
  onChange: (updated: AppSettings) => void;
}

export function GeneralTab({ settings, onChange }: Props) {
  const [newDomain, setNewDomain] = useState("");

  const handleIdleChange = (val: string) => {
    const n = parseInt(val, 10);
    if (isNaN(n) || n < 15) return;
    onChange({ ...settings, idleThresholdSeconds: n });
  };

  const handleThresholdChange = (val: string) => {
    const n = parseInt(val, 10);
    if (isNaN(n) || n < 0 || n > 100) return;
    onChange({ ...settings, reviewConfidenceThreshold: n });
  };

  const addExcludedDomain = () => {
    const domain = newDomain.trim().toLowerCase().replace(/^www\./, "");
    if (!domain || settings.excludedDomains.includes(domain)) return;
    onChange({ ...settings, excludedDomains: [...settings.excludedDomains, domain] });
    setNewDomain("");
  };

  const removeExcludedDomain = (domain: string) => {
    onChange({
      ...settings,
      excludedDomains: settings.excludedDomains.filter((d) => d !== domain),
    });
  };

  return (
    <>
      <section className="options-section">
        <h2>Tracking</h2>
        <div className="field">
          <label>Idle threshold (seconds)</label>
          <p className="field-hint">Stop tracking after this many seconds of inactivity.</p>
          <input
            type="number"
            min={15}
            max={600}
            value={settings.idleThresholdSeconds}
            onChange={(e) => handleIdleChange(e.target.value)}
          />
        </div>
        <div className="field">
          <label>Review confidence threshold</label>
          <p className="field-hint">
            Sessions assigned with confidence below this value appear in Review Needed.
          </p>
          <input
            type="number"
            min={0}
            max={100}
            value={settings.reviewConfidenceThreshold}
            onChange={(e) => handleThresholdChange(e.target.value)}
          />
        </div>
      </section>

      <section className="options-section">
        <h2>Excluded Domains</h2>
        <p className="section-hint">These domains will never be tracked.</p>
        <ul className="domain-chips">
          {settings.excludedDomains.map((d) => (
            <li key={d} className="chip">
              <span>{d}</span>
              <button className="chip-remove" onClick={() => removeExcludedDomain(d)} title="Remove">
                ×
              </button>
            </li>
          ))}
        </ul>
        <div className="add-domain-row">
          <input
            type="text"
            placeholder="e.g. reddit.com"
            value={newDomain}
            onChange={(e) => setNewDomain(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && addExcludedDomain()}
          />
          <button className="btn-add" onClick={addExcludedDomain}>Add</button>
        </div>
      </section>
    </>
  );
}
