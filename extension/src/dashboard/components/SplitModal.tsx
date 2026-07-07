import { useState } from "react";
import type { Project, Session, Tag } from "../../shared/types";
import { splitSession, type SplitSegmentSpec } from "../../shared/split-session";
import { replaceSessionWith } from "../../storage/session-repo";
import { formatDuration } from "../../shared/utils";
import { Modal } from "./Modal";
import { AssignControls, type AssignValue } from "./AssignControls";

function toLocalInput(ms: number): string {
  const d = new Date(ms);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fromLocalInput(value: string): number {
  return new Date(value).getTime();
}

interface Props {
  session: Session;
  projects: Project[];
  tags: Tag[];
  onDone: () => void;
  onClose: () => void;
}

export function SplitModal({ session, projects, tags, onDone, onClose }: Props) {
  // One boundary by default (two segments), pre-set to the midpoint.
  const mid = session.startTime + Math.floor((session.endTime - session.startTime) / 2);
  const [boundaries, setBoundaries] = useState<string[]>([toLocalInput(mid)]);
  const [segments, setSegments] = useState<AssignValue[]>([
    { projectId: session.projectId ?? "", tagIds: session.tagIds, billable: session.billable },
    { projectId: "", tagIds: [], billable: false },
  ]);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const addBoundary = () => {
    const lastBoundary = boundaries.length
      ? fromLocalInput(boundaries[boundaries.length - 1])
      : session.startTime;
    const next = lastBoundary + Math.floor((session.endTime - lastBoundary) / 2);
    setBoundaries([...boundaries, toLocalInput(next)]);
    setSegments([...segments, { projectId: "", tagIds: [], billable: false }]);
  };

  const removeBoundary = (i: number) => {
    if (boundaries.length <= 1) return;
    setBoundaries(boundaries.filter((_, idx) => idx !== i));
    setSegments(segments.filter((_, idx) => idx !== i + 1));
  };

  const handleSplit = async () => {
    setError(null);

    const specs: SplitSegmentSpec[] = segments.map((seg) => {
      const project = projects.find((p) => p.id === seg.projectId);
      return {
        projectId: seg.projectId || null,
        projectName: project?.name ?? null,
        tagIds: seg.tagIds,
        billable: seg.billable,
      };
    });

    const result = splitSession(session, {
      boundaries: boundaries.map(fromLocalInput),
      segments: specs,
    });

    if (!result.ok) {
      setError(result.error);
      return;
    }

    setSaving(true);
    await replaceSessionWith(session.id, result.sessions);
    setSaving(false);
    onDone();
  };

  const edges = [
    session.startTime,
    ...boundaries.map(fromLocalInput),
    session.endTime,
  ];

  return (
    <Modal title="Split session" onClose={onClose} wide>
      <p className="dialog-hint">
        {session.domain} · {new Date(session.startTime).toLocaleString()} →{" "}
        {new Date(session.endTime).toLocaleTimeString()} · {formatDuration(session.durationSeconds)} active.
        Active time is distributed proportionally to each segment's share of wall time.
      </p>

      {segments.map((seg, i) => (
        <div key={i} className="split-segment">
          <div className="split-segment-header">
            <strong>Segment {i + 1}</strong>
            <span className="split-segment-window">
              {isNaN(edges[i]) || isNaN(edges[i + 1])
                ? "—"
                : `${new Date(edges[i]).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })} – ${new Date(edges[i + 1]).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}`}
            </span>
          </div>
          <AssignControls
            projects={projects}
            tags={tags}
            value={seg}
            onChange={(v) => setSegments(segments.map((s, idx) => (idx === i ? v : s)))}
          />
          {i < boundaries.length && (
            <div className="split-boundary">
              <label>Split at</label>
              <input
                type="datetime-local"
                value={boundaries[i]}
                min={toLocalInput(session.startTime)}
                max={toLocalInput(session.endTime)}
                onChange={(e) =>
                  setBoundaries(boundaries.map((b, idx) => (idx === i ? e.target.value : b)))
                }
              />
              {boundaries.length > 1 && (
                <button className="btn-text" onClick={() => removeBoundary(i)}>remove</button>
              )}
            </div>
          )}
        </div>
      ))}

      <button className="btn-outline btn-small" onClick={addBoundary}>+ Add another split</button>

      {error && <div className="form-error">{error}</div>}

      <div className="modal-actions">
        <button className="btn-primary" disabled={saving} onClick={handleSplit}>
          {saving ? "Splitting…" : "Split Session"}
        </button>
        <button className="btn-cancel" onClick={onClose}>Cancel</button>
      </div>
    </Modal>
  );
}
