import { useState } from "react";
import type { Project, Session } from "../../shared/types";
import { suggestRulesFromSession, type RuleSuggestion } from "../../attribution/create-rule-from-session";
import { createRule } from "../../storage/rule-repo";
import { Modal } from "./Modal";

interface Props {
  session: Session;
  projects: Project[];
  defaultProjectId: string;
  onDone: () => void;
  onClose: () => void;
}

export function CreateRuleDialog({ session, projects, defaultProjectId, onDone, onClose }: Props) {
  const suggestions = suggestRulesFromSession(session);
  const [selected, setSelected] = useState<RuleSuggestion>(suggestions[0]);
  const [projectId, setProjectId] = useState(defaultProjectId);
  const [saving, setSaving] = useState(false);

  const handleCreate = async () => {
    if (!projectId || !selected) return;
    setSaving(true);
    const project = projects.find((p) => p.id === projectId);
    await createRule({
      projectId,
      name: `${project?.name ?? "Project"}: ${selected.label}`,
      type: selected.type,
      value: selected.value,
      queryParamName: selected.queryParamName,
      priority: 0,
      enabled: true,
    });
    setSaving(false);
    onDone();
  };

  return (
    <Modal title="Create rule for future sessions" onClose={onClose}>
      <p className="dialog-hint">
        Future sessions like this can be assigned automatically. Choose how to match them:
      </p>

      <div className="suggestion-list">
        {suggestions.map((s, i) => (
          <label key={i} className={`suggestion-option ${selected === s ? "selected" : ""}`}>
            <input
              type="radio"
              name="rule-suggestion"
              checked={selected === s}
              onChange={() => setSelected(s)}
            />
            <span className="suggestion-label">{s.label}</span>
            <code className="suggestion-value">{s.value.length > 60 ? s.value.slice(0, 60) + "…" : s.value}</code>
          </label>
        ))}
      </div>

      <div className="assign-field" style={{ marginTop: 12 }}>
        <label>Assign to project</label>
        <select value={projectId} onChange={(e) => setProjectId(e.target.value)}>
          <option value="">— Select project —</option>
          {projects.map((p) => (
            <option key={p.id} value={p.id}>{p.name}</option>
          ))}
        </select>
      </div>

      <div className="modal-actions">
        <button className="btn-primary" disabled={!projectId || saving} onClick={handleCreate}>
          {saving ? "Creating…" : "Create Rule"}
        </button>
        <button className="btn-cancel" onClick={onClose}>Cancel</button>
      </div>
    </Modal>
  );
}
