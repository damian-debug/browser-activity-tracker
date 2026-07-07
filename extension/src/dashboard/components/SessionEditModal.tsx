import { useState } from "react";
import type { Project, Session, Tag } from "../../shared/types";
import { updateSession, deleteSession } from "../../storage/session-repo";
import { Modal } from "./Modal";
import { AssignControls, type AssignValue } from "./AssignControls";

function toLocalInput(ms: number): string {
  const d = new Date(ms);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

interface Props {
  session: Session;
  projects: Project[];
  tags: Tag[];
  onDone: () => void;
  onClose: () => void;
  onSplit: () => void;
}

export function SessionEditModal({ session, projects, tags, onDone, onClose, onSplit }: Props) {
  const [assign, setAssign] = useState<AssignValue>({
    projectId: session.projectId ?? "",
    tagIds: session.tagIds,
    billable: session.billable,
  });
  const [notes, setNotes] = useState(session.notes ?? "");
  const [startStr, setStartStr] = useState(toLocalInput(session.startTime));
  const [endStr, setEndStr] = useState(toLocalInput(session.endTime));
  const [reviewed, setReviewed] = useState(session.reviewed);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    setError(null);
    const startTime = new Date(startStr).getTime();
    const endTime = new Date(endStr).getTime();
    if (isNaN(startTime) || isNaN(endTime) || endTime <= startTime) {
      setError("End time must be after start time.");
      return;
    }

    const wallSeconds = Math.floor((endTime - startTime) / 1000);
    const project = projects.find((p) => p.id === assign.projectId);
    const projectChanged = (assign.projectId || null) !== session.projectId;

    setSaving(true);
    await updateSession(session.id, {
      projectId: assign.projectId || null,
      projectName: project?.name ?? null,
      tagIds: assign.tagIds,
      billable: assign.billable,
      notes: notes.trim() || undefined,
      startTime,
      endTime,
      // Editing the window indirectly edits duration; never exceed wall time.
      durationSeconds: Math.min(session.durationSeconds, wallSeconds),
      // Picking a project is a manual assignment (reviewed by definition).
      // CLEARING the project must not fake confidence-100/reviewed, or the
      // now-unassigned session would vanish from the Review queue.
      reviewed: projectChanged && assign.projectId ? true : reviewed,
      ...(projectChanged
        ? assign.projectId
          ? { assignmentSource: "manual_dashboard" as const, assignmentConfidence: 100 }
          : { assignmentSource: "unassigned" as const, assignmentConfidence: 0, matchedRuleId: undefined }
        : {}),
    });
    setSaving(false);
    onDone();
  };

  const handleDelete = async () => {
    if (!confirm("Delete this session? This cannot be undone.")) return;
    await deleteSession(session.id);
    onDone();
  };

  return (
    <Modal title="Edit session" onClose={onClose}>
      <p className="dialog-hint" title={session.url}>
        {session.domain} · {session.title || session.url}
      </p>

      <AssignControls projects={projects} tags={tags} value={assign} onChange={setAssign} />

      <div className="field-row" style={{ marginTop: 10 }}>
        <div className="assign-field">
          <label>Start</label>
          <input type="datetime-local" value={startStr} onChange={(e) => setStartStr(e.target.value)} />
        </div>
        <div className="assign-field">
          <label>End</label>
          <input type="datetime-local" value={endStr} onChange={(e) => setEndStr(e.target.value)} />
        </div>
      </div>

      <div className="assign-field" style={{ marginTop: 10 }}>
        <label>Notes</label>
        <textarea
          rows={2}
          placeholder="Optional note for this session"
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
        />
      </div>

      <label className="checkbox-label" style={{ marginTop: 8 }}>
        <input type="checkbox" checked={reviewed} onChange={(e) => setReviewed(e.target.checked)} />
        Reviewed
      </label>

      {error && <div className="form-error">{error}</div>}

      <div className="modal-actions space-between">
        <div>
          <button className="btn-primary" disabled={saving} onClick={handleSave}>
            {saving ? "Saving…" : "Save"}
          </button>
          <button className="btn-cancel" onClick={onClose} style={{ marginLeft: 8 }}>Cancel</button>
        </div>
        <div>
          <button className="btn-outline btn-small" onClick={onSplit}>Split…</button>
          <button className="btn-danger-outline btn-small" onClick={handleDelete} style={{ marginLeft: 6 }}>
            Delete
          </button>
        </div>
      </div>
    </Modal>
  );
}
