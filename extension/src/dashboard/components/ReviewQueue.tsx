import { useMemo, useState } from "react";
import type { Project, Session, Tag } from "../../shared/types";
import { updateSession } from "../../storage/session-repo";
import { formatDuration } from "../../shared/utils";
import { AssignControls, type AssignValue } from "./AssignControls";
import { CreateRuleDialog } from "./CreateRuleDialog";

interface Props {
  sessions: Session[];   // already filtered to "needs review"
  projects: Project[];
  tags: Tag[];
  onChanged: () => void;
}

export function ReviewQueue({ sessions, projects, tags, onChanged }: Props) {
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [assign, setAssign] = useState<AssignValue>({ projectId: "", tagIds: [], billable: false });
  const [ruleDialogSession, setRuleDialogSession] = useState<Session | null>(null);
  const [lastAssignedProject, setLastAssignedProject] = useState("");

  const groups = useMemo(() => {
    const byDomain = new Map<string, Session[]>();
    for (const s of sessions) {
      const list = byDomain.get(s.domain) ?? [];
      list.push(s);
      byDomain.set(s.domain, list);
    }
    return [...byDomain.entries()]
      .map(([domain, list]) => ({
        domain,
        sessions: list.sort((a, b) => b.startTime - a.startTime),
        totalSeconds: list.reduce((sum, s) => sum + s.durationSeconds, 0),
      }))
      .sort((a, b) => b.totalSeconds - a.totalSeconds);
  }, [sessions]);

  const toggle = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleGroup = (group: { sessions: Session[] }) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      const allIn = group.sessions.every((s) => next.has(s.id));
      for (const s of group.sessions) {
        if (allIn) next.delete(s.id);
        else next.add(s.id);
      }
      return next;
    });
  };

  const applyBatch = async () => {
    if (!assign.projectId && assign.tagIds.length === 0) return;
    const project = projects.find((p) => p.id === assign.projectId);
    for (const id of selectedIds) {
      await updateSession(id, {
        projectId: assign.projectId || null,
        projectName: project?.name ?? null,
        tagIds: assign.tagIds,
        billable: assign.billable,
        assignmentSource: "manual_dashboard",
        assignmentConfidence: 100,
        reviewed: true,
      });
    }
    setLastAssignedProject(assign.projectId);
    setSelectedIds(new Set());
    onChanged();
  };

  const markReviewed = async (s: Session) => {
    await updateSession(s.id, { reviewed: true });
    onChanged();
  };

  if (sessions.length === 0) {
    return (
      <div className="empty-state review-empty">
        No sessions need review. Your tracked time is fully assigned. ✓
      </div>
    );
  }

  const selectedCount = selectedIds.size;
  const selectedSeconds = sessions
    .filter((s) => selectedIds.has(s.id))
    .reduce((sum, s) => sum + s.durationSeconds, 0);

  return (
    <div className="review-queue">
      {selectedCount > 0 && (
        <div className="batch-bar">
          <div className="batch-info">
            <strong>{selectedCount}</strong> session{selectedCount !== 1 ? "s" : ""} ·{" "}
            {formatDuration(selectedSeconds)}
          </div>
          <AssignControls projects={projects} tags={tags} value={assign} onChange={setAssign} />
          <button
            className="btn-primary"
            disabled={!assign.projectId}
            onClick={applyBatch}
          >
            Apply to selected
          </button>
        </div>
      )}

      {groups.map((group) => (
        <div key={group.domain} className="review-group">
          <div className="review-group-header">
            <label className="checkbox-label">
              <input
                type="checkbox"
                checked={group.sessions.every((s) => selectedIds.has(s.id))}
                onChange={() => toggleGroup(group)}
              />
              <strong>{group.domain}</strong>
            </label>
            <span className="review-group-meta">
              {group.sessions.length} session{group.sessions.length !== 1 ? "s" : ""} ·{" "}
              {formatDuration(group.totalSeconds)}
            </span>
          </div>
          <ul className="review-session-list">
            {group.sessions.map((s) => (
              <li key={s.id} className="review-session-row">
                <input
                  type="checkbox"
                  checked={selectedIds.has(s.id)}
                  onChange={() => toggle(s.id)}
                />
                <span className="review-session-time">
                  {new Date(s.startTime).toLocaleString(undefined, {
                    month: "short", day: "numeric", hour: "2-digit", minute: "2-digit",
                  })}
                </span>
                <span className="review-session-title" title={s.url}>
                  {s.detectedEntityName ?? s.title ?? s.url}
                </span>
                <span className="review-session-duration mono">{formatDuration(s.durationSeconds)}</span>
                <span className="review-session-actions">
                  <button
                    className="btn-text"
                    title="Create a rule from this session"
                    onClick={() => setRuleDialogSession(s)}
                  >
                    rule
                  </button>
                  <button className="btn-text" title="Mark reviewed" onClick={() => markReviewed(s)}>
                    ✓
                  </button>
                </span>
              </li>
            ))}
          </ul>
        </div>
      ))}

      {ruleDialogSession && (
        <CreateRuleDialog
          session={ruleDialogSession}
          projects={projects}
          defaultProjectId={lastAssignedProject}
          onDone={() => {
            setRuleDialogSession(null);
            onChanged();
          }}
          onClose={() => setRuleDialogSession(null)}
        />
      )}
    </div>
  );
}
