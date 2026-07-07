import type { Project, Tag } from "../../shared/types";

export interface AssignValue {
  projectId: string;
  tagIds: string[];
  billable: boolean;
}

interface Props {
  projects: Project[];
  tags: Tag[];
  value: AssignValue;
  onChange: (v: AssignValue) => void;
}

// Project + tags + billable picker shared by review batch assign and the
// session edit modal.
export function AssignControls({ projects, tags, value, onChange }: Props) {
  const toggleTag = (id: string) => {
    onChange({
      ...value,
      tagIds: value.tagIds.includes(id)
        ? value.tagIds.filter((t) => t !== id)
        : [...value.tagIds, id],
    });
  };

  return (
    <div className="assign-controls">
      <div className="assign-field">
        <label>Project</label>
        <select
          value={value.projectId}
          onChange={(e) => onChange({ ...value, projectId: e.target.value })}
        >
          <option value="">— Unassigned —</option>
          {projects.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name}{p.clientName ? ` (${p.clientName})` : ""}
            </option>
          ))}
        </select>
      </div>

      <div className="assign-field">
        <label>Tags</label>
        <div className="tag-picker">
          {tags.map((t) => (
            <button
              key={t.id}
              type="button"
              className={`tag-chip ${value.tagIds.includes(t.id) ? "selected" : ""}`}
              onClick={() => toggleTag(t.id)}
            >
              {t.name}
            </button>
          ))}
        </div>
      </div>

      <label className="checkbox-label">
        <input
          type="checkbox"
          checked={value.billable}
          onChange={(e) => onChange({ ...value, billable: e.target.checked })}
        />
        Billable
      </label>
    </div>
  );
}
