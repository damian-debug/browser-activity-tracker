import { useEffect, useState, useCallback } from "react";
import { createRoot } from "react-dom/client";
import {
  getDashboardStats,
  getSessionsInRange,
  deleteAllSessions,
  getUnsyncedSessions,
  needsReview,
} from "../storage/session-repo";
import { listProjects } from "../storage/project-repo";
import { listTags } from "../storage/tag-repo";
import type { DashboardStats, AppSettings, Project, Session, Tag } from "../shared/types";
import { DEFAULT_SETTINGS, STORAGE_KEYS } from "../shared/constants";
import { startOfDayMs, endOfDayMs } from "../shared/utils";
import { DateFilter, presetToRange, type DateRange } from "./components/DateFilter";
import { SummaryCards } from "./components/SummaryCards";
import { DomainChart } from "./components/DomainChart";
import { DomainTable } from "./components/DomainTable";
import { EntityTable } from "./components/EntityTable";
import { ProjectTotalsTable } from "./components/ProjectTotalsTable";
import { TagBreakdown } from "./components/TagBreakdown";
import { ReviewQueue } from "./components/ReviewQueue";
import { SessionLog } from "./components/SessionLog";
import "./dashboard.css";

type Tab = "projects" | "review" | "sessions" | "domains";

function Dashboard() {
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [projects, setProjects] = useState<Project[]>([]);
  const [tags, setTags] = useState<Tag[]>([]);
  const [loading, setLoading] = useState(true);
  const [dateRange, setDateRange] = useState<DateRange>(presetToRange("today"));
  const [activeTab, setActiveTab] = useState<Tab>("projects");
  const [settings, setSettings] = useState<AppSettings>(DEFAULT_SETTINGS);
  const [syncStatus, setSyncStatus] = useState<"idle" | "syncing" | "ok" | "error">("idle");
  const [unsyncedCount, setUnsyncedCount] = useState(0);

  const load = useCallback(async (range: DateRange, threshold: number) => {
    setLoading(true);
    const from = startOfDayMs(range.from);
    const to = endOfDayMs(range.to);
    const [s, sess, projs, tgs, unsynced] = await Promise.all([
      getDashboardStats(from, to, threshold),
      getSessionsInRange(from, to),
      listProjects(),
      listTags(),
      getUnsyncedSessions(),
    ]);
    setStats(s);
    setSessions(sess);
    setProjects(projs);
    setTags(tgs);
    setUnsyncedCount(unsynced.length);
    setLoading(false);
  }, []);

  useEffect(() => {
    chrome.storage.local.get(STORAGE_KEYS.SETTINGS, (result) => {
      const loaded: AppSettings = result[STORAGE_KEYS.SETTINGS]
        ? { ...DEFAULT_SETTINGS, ...result[STORAGE_KEYS.SETTINGS] }
        : DEFAULT_SETTINGS;
      setSettings(loaded);
      load(dateRange, loaded.reviewConfidenceThreshold);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const refresh = useCallback(() => {
    load(dateRange, settings.reviewConfidenceThreshold);
  }, [dateRange, settings.reviewConfidenceThreshold, load]);

  const handleRangeChange = (range: DateRange) => {
    setDateRange(range);
    load(range, settings.reviewConfidenceThreshold);
  };

  const handleExport = async () => {
    const from = startOfDayMs(dateRange.from);
    const to = endOfDayMs(dateRange.to);
    const data = await getSessionsInRange(from, to);
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `activity-${dateRange.from}-${dateRange.to}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleSync = async () => {
    if (
      stats &&
      stats.unassignedSeconds > 0 &&
      !confirm("You have unassigned time in this date range. Review it now or export it as Unassigned?\n\nOK = sync anyway · Cancel = go review")
    ) {
      setActiveTab("review");
      return;
    }
    setSyncStatus("syncing");
    chrome.runtime.sendMessage({ type: "SYNC_NOW" }, (response) => {
      if (response?.ok) {
        setSyncStatus("ok");
        setUnsyncedCount(0);
      } else {
        setSyncStatus("error");
      }
      setTimeout(() => setSyncStatus("idle"), 3000);
    });
  };

  const handleDeleteAll = async () => {
    if (!confirm("Delete ALL tracked data? This cannot be undone.")) return;
    await deleteAllSessions();
    refresh();
  };

  const reviewSessions = sessions.filter((s) =>
    needsReview(s, settings.reviewConfidenceThreshold)
  );

  return (
    <div className="dashboard">
      <header className="dash-header">
        <div className="dash-title-row">
          <h1 className="dash-title">Activity Tracker</h1>
          <div className="dash-actions">
            {settings.sync.sheetsWebhookUrl && (
              <button
                className={`btn-sync ${syncStatus}`}
                onClick={handleSync}
                disabled={syncStatus === "syncing"}
              >
                {syncStatus === "syncing" ? "Syncing…" : syncStatus === "ok" ? "Synced ✓" : syncStatus === "error" ? "Sync failed" : `Sync to Sheets${unsyncedCount > 0 ? ` (${unsyncedCount})` : ""}`}
              </button>
            )}
            <button className="btn-outline" onClick={handleExport}>Export JSON</button>
            <button className="btn-danger-outline" onClick={handleDeleteAll}>Delete All</button>
          </div>
        </div>
        <DateFilter value={dateRange} onChange={handleRangeChange} />
      </header>

      <main className="dash-main">
        {loading || !stats ? (
          <div className="dash-loading">Loading…</div>
        ) : (
          <>
            <SummaryCards stats={stats} />

            <section className="table-section">
              <div className="tab-bar">
                <button
                  className={`tab ${activeTab === "projects" ? "active" : ""}`}
                  onClick={() => setActiveTab("projects")}
                >
                  Projects
                </button>
                <button
                  className={`tab ${activeTab === "review" ? "active" : ""}`}
                  onClick={() => setActiveTab("review")}
                >
                  Review Needed
                  {reviewSessions.length > 0 && (
                    <span className="tab-badge warn">{reviewSessions.length}</span>
                  )}
                </button>
                <button
                  className={`tab ${activeTab === "sessions" ? "active" : ""}`}
                  onClick={() => setActiveTab("sessions")}
                >
                  Sessions
                </button>
                <button
                  className={`tab ${activeTab === "domains" ? "active" : ""}`}
                  onClick={() => setActiveTab("domains")}
                >
                  Domains
                </button>
              </div>

              {activeTab === "projects" && (
                <>
                  <ProjectTotalsTable stats={stats} tags={tags} />
                  <h2 className="section-title" style={{ marginTop: 24 }}>Tag Breakdown</h2>
                  <TagBreakdown stats={stats} />
                </>
              )}

              {activeTab === "review" && (
                <ReviewQueue
                  sessions={reviewSessions}
                  projects={projects}
                  tags={tags}
                  onChanged={refresh}
                />
              )}

              {activeTab === "sessions" && (
                <SessionLog
                  sessions={sessions}
                  projects={projects}
                  tags={tags}
                  onChanged={refresh}
                />
              )}

              {activeTab === "domains" && (
                <>
                  <h2 className="section-title">Time by Domain</h2>
                  <DomainChart domains={stats.domains} />
                  <DomainTable domains={stats.domains} totalSeconds={stats.totalActiveSeconds} />
                  <h2 className="section-title" style={{ marginTop: 24 }}>Detected Entities</h2>
                  <EntityTable entities={stats.entities} />
                </>
              )}
            </section>
          </>
        )}
      </main>
    </div>
  );
}

const root = createRoot(document.getElementById("root")!);
root.render(<Dashboard />);
