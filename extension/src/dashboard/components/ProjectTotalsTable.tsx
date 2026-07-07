import type { DashboardStats, Tag } from "../../shared/types";
import { formatDuration } from "../../shared/utils";

interface Props {
  stats: DashboardStats;
  tags: Tag[];
}

export function ProjectTotalsTable({ stats, tags }: Props) {
  const tagName = (id: string) => tags.find((t) => t.id === id)?.name ?? id;

  if (stats.projectTotals.length === 0) {
    return <div className="empty-state">No tracked time in this period.</div>;
  }

  return (
    <table className="data-table">
      <thead>
        <tr>
          <th>Project</th>
          <th>Client</th>
          <th className="col-right">Time</th>
          <th className="col-right">Billable</th>
          <th className="col-right">Non-billable</th>
          <th>Tags</th>
          <th className="col-right">Sessions</th>
        </tr>
      </thead>
      <tbody>
        {stats.projectTotals.map((p) => (
          <tr key={p.projectId ?? "__unassigned__"} className={p.projectId === null ? "row-unassigned" : ""}>
            <td>
              <div className="domain-cell">
                <span
                  className="project-dot"
                  style={{ background: p.projectId ? (p.color ?? "#94a3b8") : "#d1d5db" }}
                />
                <span>{p.projectName}</span>
              </div>
            </td>
            <td className="col-muted">{p.clientName ?? ""}</td>
            <td className="col-right mono">{formatDuration(p.totalSeconds)}</td>
            <td className="col-right mono">{p.billableSeconds > 0 ? formatDuration(p.billableSeconds) : "—"}</td>
            <td className="col-right mono">{p.nonBillableSeconds > 0 ? formatDuration(p.nonBillableSeconds) : "—"}</td>
            <td>
              <span className="cell-tags">
                {p.tagIds.slice(0, 3).map(tagName).join(", ")}
                {p.tagIds.length > 3 ? "…" : ""}
              </span>
            </td>
            <td className="col-right mono">{p.sessionCount}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
