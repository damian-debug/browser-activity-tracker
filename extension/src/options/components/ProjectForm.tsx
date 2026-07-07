import { useState } from "react";
import type { Project } from "../../shared/types";

const PROJECT_COLORS = [
  "#2563eb", "#7c3aed", "#db2777", "#dc2626", "#ea580c",
  "#ca8a04", "#16a34a", "#0d9488", "#0891b2", "#64748b",
];

export interface ProjectDraft {
  name: string;
  clientName: string;
  color: string;
  defaultBillable: boolean;
}

interface Props {
  initial?: Project;
  onSave: (draft: ProjectDraft) => void;
  onCancel: () => void;
}

export function ProjectForm({ initial, onSave, onCancel }: Props) {
  const [draft, setDraft] = useState<ProjectDraft>({
    name: initial?.name ?? "",
    clientName: initial?.clientName ?? "",
    color: initial?.color ?? PROJECT_COLORS[0],
    defaultBillable: initial?.defaultBillable ?? false,
  });

  return (
    <div className="project-form">
      <div className="field-row">
        <div className="field">
          <label>Project name</label>
          <input
            type="text"
            placeholder="e.g. RoleKick"
            value={draft.name}
            onChange={(e) => setDraft({ ...draft, name: e.target.value })}
            autoFocus
          />
        </div>
        <div className="field">
          <label>Client (optional)</label>
          <input
            type="text"
            placeholder="e.g. Goodspeed"
            value={draft.clientName}
            onChange={(e) => setDraft({ ...draft, clientName: e.target.value })}
          />
        </div>
      </div>

      <div className="field">
        <label>Color</label>
        <div className="color-picker">
          {PROJECT_COLORS.map((c) => (
            <button
              key={c}
              type="button"
              className={`color-swatch ${draft.color === c ? "selected" : ""}`}
              style={{ background: c }}
              onClick={() => setDraft({ ...draft, color: c })}
            />
          ))}
        </div>
      </div>

      <div className="field">
        <label className="checkbox-label">
          <input
            type="checkbox"
            checked={draft.defaultBillable}
            onChange={(e) => setDraft({ ...draft, defaultBillable: e.target.checked })}
          />
          Billable by default
        </label>
      </div>

      <div className="form-actions">
        <button className="btn-add" disabled={!draft.name.trim()} onClick={() => onSave(draft)}>
          {initial ? "Save Project" : "Create Project"}
        </button>
        <button className="btn-cancel" onClick={onCancel}>Cancel</button>
      </div>
    </div>
  );
}
