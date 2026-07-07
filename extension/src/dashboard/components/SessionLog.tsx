import { useMemo, useState } from "react";
import type { AssignmentSource, Project, Session, Tag } from "../../shared/types";
import { formatDuration } from "../../shared/utils";
import { SessionEditModal } from "./SessionEditModal";
import { SplitModal } from "./SplitModal";

interface Props {
  sessions: Session[];
  projects: Project[];
  tags: Tag[];
  onChanged: () => void;
}

interface Filters {
  projectId: string;       // "" = all, "__unassigned__" = unassigned only
  tagId: string;
  billable: string;        // "" | "yes" | "no"
  source: string;          // "" | AssignmentSource
  reviewed: string;        // "" | "yes" | "no"
}

const SOURCE_SHORT: Record<AssignmentSource, string> = {
  auto_rule: "auto",
  manual_popup: "manual",
  manual_dashboard: "manual",
  active_project_override: "override",
  suggested: "suggested",
  unassigned: "—",
};

export function SessionLog({ sessions, projects, tags, onChanged }: Props) {
  const [filters, setFilters] = useState<Filters>({
    projectId: "", tagId: "", billable: "", source: "", reviewed: "",
  });
  const [editing, setEditing] = useState<Session | null>(null);
  const [splitting, setSplitting] = useState<Session | null>(null);

  const filtered = useMemo(() => {
    return sessions
      .filter((s) => {
        if (filters.projectId === "__unassigned__" && s.projectId !== null) return false;
        if (filters.projectId && filters.projectId !== "__unassigned__" && s.projectId !== filters.projectId) return false;
        if (filters.tagId && !s.tagIds.includes(filters.tagId)) return false;
        if (filters.billable === "yes" && !s.billable) return false;
        if (filters.billable === "no" && s.billable) return false;
        if (filters.source && s.assignmentSource !== filters.source) return false;
        if (filters.reviewed === "yes" && !s.reviewed) return false;
        if (filters.reviewed === "no" && s.reviewed) return false;
        return true;
      })
      .sort((a, b) => b.startTime - a.startTime);
  }, [sessions, filters]);

  const set = (patch: Partial<Filters>) => setFilters((f) => ({ ...f, ...patch }));

  return (
    <div className="session-log">
      <div className="filter-bar">
        <select value={filters.projectId} onChange={(e) => set({ projectId: e.target.value })}>
          <option value="">All projects</option>
          <option value="__unassigned__">Unassigned</option>
          {projects.map((p) => (
            <option key={p.id} value={p.id}>{p.name}</option>
          ))}
        </select>
        <select value={filters.tagId} onChange={(e) => set({ tagId: e.target.value })}>
          <option value="">All tags</option>
          {tags.map((t) => (
            <option key={t.id} value={t.id}>{t.name}</option>
          ))}
        </select>
        <select value={filters.billable} onChange={(e) => set({ billable: e.target.value })}>
          <option value="">Billable + non-billable</option>
          <option value="yes">Billable only</option>
          <option value="no">Non-billable only</option>
        </select>
        <select value={filters.source} onChange={(e) => set({ source: e.target.value })}>
          <option value="">Any source</option>
          <option value="auto_rule">Auto (rule)</option>
          <option value="manual_popup">Manual (popup)</option>
          <option value="manual_dashboard">Manual (dashboard)</option>
          <option value="active_project_override">Override</option>
          <option value="unassigned">Unassigned</option>
        </select>
        <select value={filters.reviewed} onChange={(e) => set({ reviewed: e.target.value })}>
          <option value="">Reviewed + unreviewed</option>
          <option value="yes">Reviewed</option>
          <option value="no">Unreviewed</option>
        </select>
        <span className="filter-count">{filtered.length} session{filtered.length !== 1 ? "s" : ""}</span>
      </div>

      <table className="data-table session-table">
        <thead>
          <tr>
            <th>Start</th>
            <th className="col-right">Duration</th>
            <th>Project</th>
            <th>Tags</th>
            <th>Billable</th>
            <th>Domain / Title</th>
            <th>Source</th>
            <th className="col-right">Conf.</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {filtered.map((s) => {
            const project = s.projectId ? projects.find((p) => p.id === s.projectId) : null;
            return (
              <tr key={s.id} className={s.reviewed ? "" : "row-unreviewed"}>
                <td className="col-muted mono">
                  {new Date(s.startTime).toLocaleString(undefined, {
                    month: "short", day: "numeric", hour: "2-digit", minute: "2-digit",
                  })}
                </td>
                <td className="col-right mono">{formatDuration(s.durationSeconds)}</td>
                <td>
                  {project ? (
                    <span className="domain-cell">
                      <span className="project-dot" style={{ background: project.color ?? "#94a3b8" }} />
                      {project.name}
                    </span>
                  ) : (
                    <span className="unassigned-text">Unassigned</span>
                  )}
                </td>
                <td className="cell-tags">
                  {s.tagIds.map((id) => tags.find((t) => t.id === id)?.name).filter(Boolean).join(", ")}
                </td>
                <td>{s.billable ? "✓" : ""}</td>
                <td className="session-title-cell" title={s.url}>
                  <span className="session-domain">{s.domain}</span>
                  <span className="session-title">{s.detectedEntityName ?? s.title}</span>
                </td>
                <td className="col-muted">{SOURCE_SHORT[s.assignmentSource]}</td>
                <td className="col-right col-muted mono">{s.assignmentConfidence || ""}</td>
                <td>
                  <button className="btn-text" onClick={() => setEditing(s)}>edit</button>
                </td>
              </tr>
            );
          })}
          {filtered.length === 0 && (
            <tr><td colSpan={9} className="empty-state">No sessions match these filters.</td></tr>
          )}
        </tbody>
      </table>

      {editing && !splitting && (
        <SessionEditModal
          session={editing}
          projects={projects}
          tags={tags}
          onDone={() => { setEditing(null); onChanged(); }}
          onClose={() => setEditing(null)}
          onSplit={() => setSplitting(editing)}
        />
      )}

      {splitting && (
        <SplitModal
          session={splitting}
          projects={projects}
          tags={tags}
          onDone={() => { setSplitting(null); setEditing(null); onChanged(); }}
          onClose={() => setSplitting(null)}
        />
      )}
    </div>
  );
}
