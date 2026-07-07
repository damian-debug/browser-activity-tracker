import { useMemo, useState } from "react";
import type { Project, ProjectRule, ProjectRuleType, Tag } from "../../shared/types";
import { runRuleEngine } from "../../attribution/rule-engine";
import { extractDomain } from "../../shared/utils";

const RULE_TYPES: { value: ProjectRuleType; label: string }[] = [
  { value: "domain_equals", label: "Domain equals" },
  { value: "url_contains", label: "URL contains" },
  { value: "url_starts_with", label: "URL starts with" },
  { value: "path_contains", label: "Path contains" },
  { value: "query_param_equals", label: "Query parameter equals" },
  { value: "title_contains", label: "Title contains" },
  { value: "regex", label: "Regex (advanced)" },
];

export interface RuleDraft {
  name: string;
  type: ProjectRuleType;
  value: string;
  queryParamName: string;
  priority: number;
  enabled: boolean;
  defaultTagIds: string[];
  defaultBillable: boolean | undefined;
}

interface Props {
  project: Project;
  tags: Tag[];
  initial?: ProjectRule;
  onSave: (draft: RuleDraft) => void;
  onCancel: () => void;
}

export function RuleForm({ project, tags, initial, onSave, onCancel }: Props) {
  const [draft, setDraft] = useState<RuleDraft>({
    name: initial?.name ?? "",
    type: initial?.type ?? "url_contains",
    value: initial?.value ?? "",
    queryParamName: initial?.queryParamName ?? "",
    priority: initial?.priority ?? 0,
    enabled: initial?.enabled ?? true,
    defaultTagIds: initial?.defaultTagIds ?? [],
    defaultBillable: initial?.defaultBillable,
  });
  const [testInput, setTestInput] = useState("");

  // Live test: run the REAL engine against the pasted URL/title with just this
  // rule, so what the user sees here is exactly what the tracker will do.
  const testResult = useMemo(() => {
    if (!testInput.trim() || !draft.value.trim()) return null;
    const url = testInput.trim();
    const candidate: ProjectRule = {
      id: "test",
      projectId: project.id,
      name: draft.name || "test",
      type: draft.type,
      value: draft.value,
      queryParamName: draft.queryParamName || undefined,
      priority: draft.priority,
      enabled: true,
      createdAt: 0,
      updatedAt: 0,
    };
    const result = runRuleEngine(
      {
        url,
        domain: extractDomain(url) ?? url,
        title: testInput,
        service: null,
        detectedEntityId: null,
        detectedEntityName: null,
      },
      [candidate]
    );
    return result;
  }, [testInput, draft, project.id]);

  const toggleTag = (id: string) => {
    setDraft((d) => ({
      ...d,
      defaultTagIds: d.defaultTagIds.includes(id)
        ? d.defaultTagIds.filter((t) => t !== id)
        : [...d.defaultTagIds, id],
    }));
  };

  const canSave = draft.name.trim() && draft.value.trim() &&
    (draft.type !== "query_param_equals" || draft.queryParamName.trim());

  return (
    <div className="rule-form">
      <div className="field">
        <label>Rule name</label>
        <input
          type="text"
          placeholder='e.g. "RoleKick Bubble editor"'
          value={draft.name}
          onChange={(e) => setDraft({ ...draft, name: e.target.value })}
        />
      </div>

      <div className="field-row">
        <div className="field">
          <label>Type</label>
          <select
            value={draft.type}
            onChange={(e) => setDraft({ ...draft, type: e.target.value as ProjectRuleType })}
          >
            {RULE_TYPES.map((t) => (
              <option key={t.value} value={t.value}>{t.label}</option>
            ))}
          </select>
        </div>
        <div className="field">
          <label>Priority</label>
          <input
            type="number"
            value={draft.priority}
            onChange={(e) => setDraft({ ...draft, priority: parseInt(e.target.value, 10) || 0 })}
          />
        </div>
      </div>

      {draft.type === "query_param_equals" && (
        <div className="field">
          <label>Query parameter name</label>
          <input
            type="text"
            placeholder="e.g. id"
            value={draft.queryParamName}
            onChange={(e) => setDraft({ ...draft, queryParamName: e.target.value })}
          />
        </div>
      )}

      <div className="field">
        <label>{draft.type === "query_param_equals" ? "Parameter value" : "Value"}</label>
        <input
          type="text"
          placeholder={
            draft.type === "domain_equals" ? "e.g. bubble.io" :
            draft.type === "regex" ? "e.g. github\\.com\\/org\\/repo.*" :
            "e.g. figma.com/design/abc123"
          }
          value={draft.value}
          onChange={(e) => setDraft({ ...draft, value: e.target.value })}
        />
      </div>

      <div className="field">
        <label>Default tags</label>
        <div className="tag-picker">
          {tags.map((t) => (
            <button
              key={t.id}
              type="button"
              className={`tag-chip ${draft.defaultTagIds.includes(t.id) ? "selected" : ""}`}
              onClick={() => toggleTag(t.id)}
            >
              {t.name}
            </button>
          ))}
        </div>
      </div>

      <div className="field-row">
        <div className="field">
          <label>Billable</label>
          <select
            value={draft.defaultBillable === undefined ? "inherit" : draft.defaultBillable ? "yes" : "no"}
            onChange={(e) =>
              setDraft({
                ...draft,
                defaultBillable: e.target.value === "inherit" ? undefined : e.target.value === "yes",
              })
            }
          >
            <option value="inherit">Project default ({project.defaultBillable ? "billable" : "non-billable"})</option>
            <option value="yes">Billable</option>
            <option value="no">Non-billable</option>
          </select>
        </div>
        <div className="field">
          <label className="checkbox-label" style={{ marginTop: 22 }}>
            <input
              type="checkbox"
              checked={draft.enabled}
              onChange={(e) => setDraft({ ...draft, enabled: e.target.checked })}
            />
            Enabled
          </label>
        </div>
      </div>

      <div className="rule-tester">
        <label>Test this rule</label>
        <input
          type="text"
          placeholder="Paste a URL or title to test against"
          value={testInput}
          onChange={(e) => setTestInput(e.target.value)}
        />
        {testResult && (
          <div className={`test-result ${testResult.projectId ? "matched" : "not-matched"}`}>
            {testResult.projectId ? (
              <>✓ Matched → {project.name} (confidence {testResult.assignmentConfidence})</>
            ) : (
              <>✗ Not matched</>
            )}
          </div>
        )}
      </div>

      <div className="form-actions">
        <button className="btn-add" disabled={!canSave} onClick={() => onSave(draft)}>
          {initial ? "Save Rule" : "Add Rule"}
        </button>
        <button className="btn-cancel" onClick={onCancel}>Cancel</button>
      </div>
    </div>
  );
}
