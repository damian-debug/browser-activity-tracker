import { useMemo, useState } from "react";
import type { Project, Session } from "../../shared/types";
import { suggestRulesFromSession } from "../../attribution/create-rule-from-session";
import { applyRuleToExistingSessions } from "../../attribution/apply-rule-to-sessions";
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
  // Memoized so re-renders don't rebuild the array — and the selection is
  // tracked by INDEX, not object identity, so unrelated state changes (like
  // picking a project) can't orphan the checked radio.
  const suggestions = useMemo(() => suggestRulesFromSession(session), [session]);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [projectId, setProjectId] = useState(defaultProjectId);
  const [saving, setSaving] = useState(false);

  const selected = suggestions[selectedIndex];

  const handleCreate = async () => {
    if (!projectId || !selected) return;
    setSaving(true);
    const project = projects.find((p) => p.id === projectId);
    const rule = await createRule({
      projectId,
      name: `${project?.name ?? "Project"}: ${selected.label}`,
      type: selected.type,
      value: selected.value,
      queryParamName: selected.queryParamName,
      priority: 0,
      enabled: true,
    });
    // Resolve the session(s) this rule was created from: sweep existing
    // unassigned, unreviewed sessions that match it out of the Review queue.
    await applyRuleToExistingSessions(rule);
    setSaving(false);
    onDone();
  };

  return (
    <Modal title="Create rule for future sessions" onClose={onClose}>
      <p className="dialog-hint">
        Future sessions like this will be assigned automatically, and existing unassigned
        sessions that match will be resolved right away. Choose how to match them:
      </p>

      <div className="suggestion-list">
        {suggestions.map((s, i) => (
          <label key={i} className={`suggestion-option ${selectedIndex === i ? "selected" : ""}`}>
            <input
              type="radio"
              name="rule-suggestion"
              checked={selectedIndex === i}
              onChange={() => setSelectedIndex(i)}
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
