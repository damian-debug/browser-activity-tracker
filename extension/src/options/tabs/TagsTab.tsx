import { useEffect, useState } from "react";
import type { Tag } from "../../shared/types";
import { listTags, createTag, updateTag, deleteTag } from "../../storage/tag-repo";

const TAG_COLORS = [
  "#2563eb", "#7c3aed", "#db2777", "#dc2626", "#ea580c",
  "#ca8a04", "#16a34a", "#0d9488", "#0891b2", "#64748b",
];

export function TagsTab() {
  const [tags, setTags] = useState<Tag[]>([]);
  const [newName, setNewName] = useState("");
  const [editing, setEditing] = useState<Tag | null>(null);
  const [editName, setEditName] = useState("");

  const refresh = async () => setTags(await listTags());

  useEffect(() => {
    refresh();
  }, []);

  const handleCreate = async () => {
    const name = newName.trim();
    if (!name || tags.some((t) => t.name.toLowerCase() === name.toLowerCase())) return;
    await createTag(name);
    setNewName("");
    await refresh();
  };

  const startEdit = (tag: Tag) => {
    setEditing(tag);
    setEditName(tag.name);
  };

  const handleSaveEdit = async () => {
    if (!editing || !editName.trim()) return;
    await updateTag(editing.id, { name: editName.trim() });
    setEditing(null);
    await refresh();
  };

  const handleSetColor = async (tag: Tag, color: string) => {
    await updateTag(tag.id, { color });
    await refresh();
  };

  const handleDelete = async (tag: Tag) => {
    if (!confirm(`Delete tag "${tag.name}"? It will be removed from all sessions.`)) return;
    await deleteTag(tag.id);
    await refresh();
  };

  return (
    <section className="options-section">
      <h2>Tags</h2>
      <p className="section-hint">
        Tags describe the type of work (Development, Design, QA…). A session can have several.
      </p>

      <div className="add-domain-row" style={{ marginBottom: 16 }}>
        <input
          type="text"
          placeholder="New tag name"
          value={newName}
          onChange={(e) => setNewName(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && handleCreate()}
        />
        <button className="btn-add" onClick={handleCreate}>Add</button>
      </div>

      <ul className="tags-manage-list">
        {tags.map((tag) => (
          <li key={tag.id} className="tag-manage-row">
            {editing?.id === tag.id ? (
              <>
                <input
                  type="text"
                  value={editName}
                  onChange={(e) => setEditName(e.target.value)}
                  onKeyDown={(e) => e.key === "Enter" && handleSaveEdit()}
                  autoFocus
                />
                <button className="btn-add btn-small" onClick={handleSaveEdit}>Save</button>
                <button className="btn-cancel btn-small" onClick={() => setEditing(null)}>Cancel</button>
              </>
            ) : (
              <>
                <span className="tag-color-swatches">
                  {TAG_COLORS.map((c) => (
                    <button
                      key={c}
                      className={`color-swatch tiny ${tag.color === c ? "selected" : ""}`}
                      style={{ background: c }}
                      onClick={() => handleSetColor(tag, c)}
                      title="Set color"
                    />
                  ))}
                </span>
                <span className="tag-manage-name" style={{ color: tag.color }}>{tag.name}</span>
                <span className="tag-manage-actions">
                  <button className="icon-btn" title="Rename" onClick={() => startEdit(tag)}>✎</button>
                  <button className="icon-btn" title="Delete" onClick={() => handleDelete(tag)}>🗑</button>
                </span>
              </>
            )}
          </li>
        ))}
        {tags.length === 0 && <li className="empty-state">No tags.</li>}
      </ul>
    </section>
  );
}
