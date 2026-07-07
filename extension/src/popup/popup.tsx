import { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { getTodayStats } from "../storage/session-repo";
import { listProjects } from "../storage/project-repo";
import { listTags } from "../storage/tag-repo";
import type {
  ActiveProjectOverrideExpires,
  ActiveProjectOverrideScope,
  AssignmentSource,
  DashboardStats,
  Project,
  Tag,
} from "../shared/types";
import { formatDuration } from "../shared/utils";
import "./popup.css";

interface ActiveInfo {
  domain: string;
  title: string;
  service: string | null;
  detectedEntityName: string | null;
  projectId: string | null;
  projectName: string | null;
  tagIds: string[];
  billable: boolean;
  assignmentSource: AssignmentSource;
  assignmentConfidence: number;
  durationSeconds: number;
  paused: boolean;
}

const SOURCE_LABELS: Record<AssignmentSource, string> = {
  auto_rule: "Auto (rule)",
  manual_popup: "Manual",
  manual_dashboard: "Manual",
  active_project_override: "Manual override",
  suggested: "Suggested",
  unassigned: "Unassigned",
};

function Popup() {
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [active, setActive] = useState<ActiveInfo | null>(null);
  const [projects, setProjects] = useState<Project[]>([]);
  const [tags, setTags] = useState<Tag[]>([]);

  // Switcher state
  const [editing, setEditing] = useState(false);
  const [selProject, setSelProject] = useState<string>("");
  const [selTags, setSelTags] = useState<string[]>([]);
  const [selBillable, setSelBillable] = useState(false);
  const [selScope, setSelScope] = useState<ActiveProjectOverrideScope>("current_domain");
  const [selExpires, setSelExpires] = useState<ActiveProjectOverrideExpires>("manual");
  const [applying, setApplying] = useState(false);

  const pollActive = () => {
    chrome.runtime.sendMessage({ type: "GET_ACTIVE" }, (res) => {
      setActive((res as ActiveInfo | null) ?? null);
    });
  };

  useEffect(() => {
    getTodayStats().then(setStats);
    listProjects().then(setProjects);
    listTags().then(setTags);
    pollActive();
    const interval = setInterval(pollActive, 2000);
    return () => clearInterval(interval);
  }, []);

  const openEditor = () => {
    if (!active) return;
    setSelProject(active.projectId ?? "");
    setSelTags(active.tagIds);
    setSelBillable(active.billable);
    setEditing(true);
  };

  const apply = () => {
    const project = projects.find((p) => p.id === selProject);
    if (!project) return;
    setApplying(true);
    chrome.runtime.sendMessage(
      {
        type: "SWITCH_PROJECT",
        payload: {
          projectId: project.id,
          projectName: project.name,
          tagIds: selTags,
          billable: selBillable,
          scope: selScope,
          expires: selExpires,
        },
      },
      () => {
        setApplying(false);
        setEditing(false);
        pollActive();
        getTodayStats().then(setStats);
      }
    );
  };

  const clearOverride = () => {
    chrome.runtime.sendMessage({ type: "CLEAR_OVERRIDE" }, () => {
      setEditing(false);
      pollActive();
    });
  };

  const toggleTag = (id: string) => {
    setSelTags((t) => (t.includes(id) ? t.filter((x) => x !== id) : [...t, id]));
  };

  const openDashboard = () => {
    chrome.tabs.create({ url: chrome.runtime.getURL("dashboard.html") });
  };

  const openOptions = () => chrome.runtime.openOptionsPage();

  const isManual =
    active &&
    (active.assignmentSource === "manual_popup" ||
      active.assignmentSource === "active_project_override");

  return (
    <div className="popup">
      <header className="popup-header">
        <span className="popup-title">Activity Tracker</span>
        <button onClick={openOptions} className="icon-btn" title="Settings">⚙</button>
      </header>

      {active && (
        <div className={`active-card ${active.paused ? "paused" : ""}`}>
          <div className="active-dot" />
          <div className="active-info">
            <div className="active-domain">
              {active.service && <span className="service-badge">{active.service}</span>}
              {active.detectedEntityName ?? active.domain}
            </div>
            <div className="active-time">
              {active.paused ? "Paused" : formatDuration(active.durationSeconds)}
            </div>
          </div>
        </div>
      )}

      {active && !editing && (
        <div className="assignment-card" onClick={openEditor} title="Click to change">
          <div className="assignment-row">
            <span className="assignment-label">Project</span>
            <span className={`assignment-value ${!active.projectId ? "unassigned" : ""}`}>
              {active.projectName ?? "Unassigned"}
            </span>
          </div>
          <div className="assignment-meta">
            <span className={`source-badge ${isManual ? "manual" : active.projectId ? "auto" : "none"}`}>
              {SOURCE_LABELS[active.assignmentSource]}
            </span>
            {active.billable && <span className="billable-badge">Billable</span>}
            {active.tagIds.length > 0 && (
              <span className="popup-tags">
                {active.tagIds
                  .map((id) => tags.find((t) => t.id === id)?.name)
                  .filter(Boolean)
                  .join(", ")}
              </span>
            )}
            <span className="change-hint">change ▾</span>
          </div>
        </div>
      )}

      {active && editing && (
        <div className="switcher">
          <div className="switcher-field">
            <label>Project</label>
            <select value={selProject} onChange={(e) => setSelProject(e.target.value)}>
              <option value="">— Select project —</option>
              {projects.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}{p.clientName ? ` (${p.clientName})` : ""}
                </option>
              ))}
            </select>
          </div>

          <div className="switcher-field">
            <label>Tags</label>
            <div className="tag-picker">
              {tags.map((t) => (
                <button
                  key={t.id}
                  className={`tag-chip ${selTags.includes(t.id) ? "selected" : ""}`}
                  onClick={() => toggleTag(t.id)}
                >
                  {t.name}
                </button>
              ))}
            </div>
          </div>

          <div className="switcher-row">
            <label className="billable-toggle">
              <input
                type="checkbox"
                checked={selBillable}
                onChange={(e) => setSelBillable(e.target.checked)}
              />
              Billable
            </label>
          </div>

          <div className="switcher-field">
            <label>Apply to</label>
            <select value={selScope} onChange={(e) => setSelScope(e.target.value as ActiveProjectOverrideScope)}>
              <option value="current_tab">This tab</option>
              <option value="current_domain">This domain ({active.domain})</option>
              <option value="global">All browser activity</option>
            </select>
          </div>

          <div className="switcher-field">
            <label>Until</label>
            <select value={selExpires} onChange={(e) => setSelExpires(e.target.value as ActiveProjectOverrideExpires)}>
              <option value="manual">I switch manually</option>
              <option value="thirty_minutes">30 minutes</option>
              <option value="end_of_day">End of day</option>
            </select>
          </div>

          <p className="switch-warning">
            Switching ends the current session and starts a new one for this tab.
          </p>

          <div className="switcher-actions">
            <button className="btn-primary" disabled={!selProject || applying} onClick={apply}>
              {applying ? "Applying…" : "Apply"}
            </button>
            {isManual && (
              <button className="btn-text" onClick={clearOverride}>Back to auto</button>
            )}
            <button className="btn-text" onClick={() => setEditing(false)}>Cancel</button>
          </div>
        </div>
      )}

      {stats ? (
        <>
          <div className="today-summary">
            <div className="summary-item">
              <span className="summary-value">{formatDuration(stats.totalActiveSeconds)}</span>
              <span className="summary-label">Today</span>
            </div>
            <div className="summary-item">
              <span className="summary-value">{formatDuration(stats.billableSeconds)}</span>
              <span className="summary-label">Billable</span>
            </div>
            <div className="summary-item">
              <span className={`summary-value ${stats.unassignedSeconds > 0 ? "warn" : ""}`}>
                {formatDuration(stats.unassignedSeconds)}
              </span>
              <span className="summary-label">Unassigned</span>
            </div>
          </div>

          <div className="section-label">Top Projects Today</div>
          <ul className="domain-list">
            {stats.projectTotals.slice(0, 5).map((p) => (
              <li key={p.projectId ?? "unassigned"} className="domain-row">
                <span className="domain-name">
                  <span
                    className="project-dot"
                    style={{ background: p.projectId ? (p.color ?? "#94a3b8") : "#d1d5db" }}
                  />
                  {p.projectName}
                </span>
                <span className="domain-time">{formatDuration(p.totalSeconds)}</span>
              </li>
            ))}
            {stats.projectTotals.length === 0 && (
              <li className="empty-state">No activity recorded yet</li>
            )}
          </ul>
        </>
      ) : (
        <div className="loading">Loading…</div>
      )}

      <footer className="popup-footer">
        <button className="btn-primary" onClick={openDashboard}>Open Dashboard</button>
      </footer>
    </div>
  );
}

const root = createRoot(document.getElementById("root")!);
root.render(<Popup />);
