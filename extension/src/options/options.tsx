import { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import type { AppSettings } from "../shared/types";
import { DEFAULT_SETTINGS, STORAGE_KEYS } from "../shared/constants";
import { GeneralTab } from "./tabs/GeneralTab";
import { ProjectsTab } from "./tabs/ProjectsTab";
import { TagsTab } from "./tabs/TagsTab";
import { SyncTab } from "./tabs/SyncTab";
import "./options.css";

type TabId = "general" | "projects" | "tags" | "sync";

const TABS: { id: TabId; label: string }[] = [
  { id: "general", label: "General" },
  { id: "projects", label: "Projects" },
  { id: "tags", label: "Tags" },
  { id: "sync", label: "Sheets Sync" },
];

function Options() {
  const [settings, setSettings] = useState<AppSettings>(DEFAULT_SETTINGS);
  const [saved, setSaved] = useState(false);
  const [tab, setTab] = useState<TabId>(
    (new URLSearchParams(location.search).get("tab") as TabId) || "general"
  );

  useEffect(() => {
    chrome.storage.local.get(STORAGE_KEYS.SETTINGS, (result) => {
      if (result[STORAGE_KEYS.SETTINGS]) {
        setSettings({ ...DEFAULT_SETTINGS, ...result[STORAGE_KEYS.SETTINGS] });
      }
    });
  }, []);

  const handleSettingsChange = (updated: AppSettings) => {
    setSettings(updated);
    chrome.storage.local.set({ [STORAGE_KEYS.SETTINGS]: updated }, () => {
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    });
  };

  return (
    <div className="options">
      <header className="options-header">
        <h1>Activity Tracker Settings</h1>
        {saved && <span className="saved-badge">Saved</span>}
      </header>

      <nav className="options-tabs">
        {TABS.map((t) => (
          <button
            key={t.id}
            className={`options-tab ${tab === t.id ? "active" : ""}`}
            onClick={() => setTab(t.id)}
          >
            {t.label}
          </button>
        ))}
      </nav>

      <div className="options-body">
        {tab === "general" && <GeneralTab settings={settings} onChange={handleSettingsChange} />}
        {tab === "projects" && <ProjectsTab />}
        {tab === "tags" && <TagsTab />}
        {tab === "sync" && <SyncTab settings={settings} onChange={handleSettingsChange} />}

        <section className="options-section">
          <h2>About</h2>
          <p className="about-text">
            Browser Activity Tracker v2.0.0 — all data is stored locally on your machine. Nothing is
            sent externally unless you configure the Sheets webhook.
          </p>
        </section>
      </div>
    </div>
  );
}

const root = createRoot(document.getElementById("root")!);
root.render(<Options />);
