import { useEffect, useState, useCallback } from "react";
import type { Project, ProjectRule, Tag } from "../../shared/types";
import {
  listProjects, createProject, updateProject, archiveProject,
} from "../../storage/project-repo";
import { listRules, createRule, updateRule, deleteRule } from "../../storage/rule-repo";
import { listTags } from "../../storage/tag-repo";
import { ProjectForm, type ProjectDraft } from "../components/ProjectForm";
import { RuleForm, type RuleDraft } from "../components/RuleForm";

const RULE_TYPE_LABELS: Record<string, string> = {
  domain_equals: "Domain",
  url_contains: "URL contains",
  url_starts_with: "URL starts with",
  path_contains: "Path contains",
  query_param_equals: "Query param",
  title_contains: "Title contains",
  regex: "Regex",
};

export function ProjectsTab() {
  const [projects, setProjects] = useState<Project[]>([]);
  const [showArchived, setShowArchived] = useState(false);
  const [selected, setSelected] = useState<Project | null>(null);
  const [rules, setRules] = useState<ProjectRule[]>([]);
  const [tags, setTags] = useState<Tag[]>([]);
  const [creating, setCreating] = useState(false);
  const [editingProject, setEditingProject] = useState(false);
  const [editingRule, setEditingRule] = useState<ProjectRule | "new" | null>(null);

  const refresh = useCallback(async () => {
    const all = await listProjects(true);
    setProjects(all);
    setTags(await listTags());
    if (selected) {
      const fresh = all.find((p) => p.id === selected.id) ?? null;
      setSelected(fresh);
      setRules(fresh ? await listRules(fresh.id) : []);
    }
  }, [selected]);

  useEffect(() => {
    refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const selectProject = async (p: Project) => {
    setSelected(p);
    setEditingProject(false);
    setEditingRule(null);
    setRules(await listRules(p.id));
  };

  const handleCreateProject = async (draft: ProjectDraft) => {
    const p = await createProject({
      name: draft.name.trim(),
      clientName: draft.clientName.trim() || undefined,
      color: draft.color,
      defaultBillable: draft.defaultBillable,
    });
    setCreating(false);
    await refresh();
    await selectProject(p);
  };

  const handleUpdateProject = async (draft: ProjectDraft) => {
    if (!selected) return;
    await updateProject(selected.id, {
      name: draft.name.trim(),
      clientName: draft.clientName.trim() || undefined,
      color: draft.color,
      defaultBillable: draft.defaultBillable,
    });
    setEditingProject(false);
    await refresh();
  };

  const handleArchive = async (p: Project) => {
    await archiveProject(p.id, !p.archived);
    await refresh();
  };

  const handleSaveRule = async (draft: RuleDraft) => {
    if (!selected) return;
    const data = {
      projectId: selected.id,
      name: draft.name.trim(),
      type: draft.type,
      value: draft.value.trim(),
      queryParamName: draft.queryParamName.trim() || undefined,
      priority: draft.priority,
      enabled: draft.enabled,
      defaultTagIds: draft.defaultTagIds.length ? draft.defaultTagIds : undefined,
      defaultBillable: draft.defaultBillable,
    };
    if (editingRule && editingRule !== "new") {
      await updateRule(editingRule.id, data);
    } else {
      await createRule(data);
    }
    setEditingRule(null);
    setRules(await listRules(selected.id));
  };

  const handleDeleteRule = async (rule: ProjectRule) => {
    if (!confirm(`Delete rule "${rule.name}"?`)) return;
    await deleteRule(rule.id);
    if (selected) setRules(await listRules(selected.id));
  };

  const visible = showArchived ? projects : projects.filter((p) => !p.archived);

  return (
    <section className="options-section projects-layout">
      <div className="projects-sidebar">
        <div className="projects-sidebar-header">
          <h2>Projects</h2>
          <button className="btn-add btn-small" onClick={() => { setCreating(true); setSelected(null); }}>
            + New
          </button>
        </div>
        <ul className="project-list">
          {visible.map((p) => (
            <li
              key={p.id}
              className={`project-list-item ${selected?.id === p.id ? "selected" : ""} ${p.archived ? "archived" : ""}`}
              onClick={() => selectProject(p)}
            >
              <span className="project-dot" style={{ background: p.color ?? "#94a3b8" }} />
              <span className="project-list-name">{p.name}</span>
              {p.clientName && <span className="project-list-client">{p.clientName}</span>}
            </li>
          ))}
          {visible.length === 0 && <li className="empty-state">No projects yet.</li>}
        </ul>
        <label className="checkbox-label show-archived">
          <input
            type="checkbox"
            checked={showArchived}
            onChange={(e) => setShowArchived(e.target.checked)}
          />
          Show archived
        </label>
      </div>

      <div className="projects-detail">
        {creating ? (
          <>
            <h3>New Project</h3>
            <ProjectForm onSave={handleCreateProject} onCancel={() => setCreating(false)} />
          </>
        ) : selected ? (
          <>
            <div className="project-detail-header">
              <h3>
                <span className="project-dot" style={{ background: selected.color ?? "#94a3b8" }} />
                {selected.name}
                {selected.archived && <span className="archived-badge">Archived</span>}
              </h3>
              <div className="detail-actions">
                <button className="btn-outline btn-small" onClick={() => setEditingProject(true)}>Edit</button>
                <button className="btn-outline btn-small" onClick={() => handleArchive(selected)}>
                  {selected.archived ? "Unarchive" : "Archive"}
                </button>
              </div>
            </div>

            {editingProject && (
              <ProjectForm
                initial={selected}
                onSave={handleUpdateProject}
                onCancel={() => setEditingProject(false)}
              />
            )}

            <div className="rules-header">
              <h4>Rules</h4>
              <button className="btn-add btn-small" onClick={() => setEditingRule("new")}>+ Add Rule</button>
            </div>
            <p className="section-hint">
              Rules automatically assign new browser sessions to this project.
            </p>

            {editingRule && (
              <RuleForm
                project={selected}
                tags={tags}
                initial={editingRule === "new" ? undefined : editingRule}
                onSave={handleSaveRule}
                onCancel={() => setEditingRule(null)}
              />
            )}

            <ul className="rule-list">
              {rules.map((r) => (
                <li key={r.id} className={`rule-item ${r.enabled ? "" : "disabled"}`}>
                  <div className="rule-info">
                    <span className="rule-name">{r.name}</span>
                    <span className="rule-desc">
                      {RULE_TYPE_LABELS[r.type]}
                      {r.type === "query_param_equals" && r.queryParamName ? ` ${r.queryParamName}=` : ": "}
                      <code>{r.value}</code>
                      {r.priority !== 0 && <span className="rule-priority"> · priority {r.priority}</span>}
                      {!r.enabled && <span className="rule-disabled-badge"> · disabled</span>}
                    </span>
                  </div>
                  <div className="rule-actions">
                    <button className="icon-btn" title="Edit" onClick={() => setEditingRule(r)}>✎</button>
                    <button className="icon-btn" title="Delete" onClick={() => handleDeleteRule(r)}>🗑</button>
                  </div>
                </li>
              ))}
              {rules.length === 0 && !editingRule && (
                <li className="empty-state">No rules yet. Time on matching pages will stay Unassigned.</li>
              )}
            </ul>
          </>
        ) : (
          <div className="empty-state detail-empty">
            Select a project to manage its details and rules, or create a new one.
          </div>
        )}
      </div>
    </section>
  );
}
