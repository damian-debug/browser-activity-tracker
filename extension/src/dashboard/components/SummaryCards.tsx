import type { DashboardStats } from "../../shared/types";
import { formatDurationLong } from "../../shared/utils";

interface Props {
  stats: DashboardStats;
}

export function SummaryCards({ stats }: Props) {
  const topProject = stats.projectTotals.find((p) => p.projectId !== null);

  const cards = [
    { label: "Tracked", value: formatDurationLong(stats.totalActiveSeconds) },
    { label: "Billable", value: formatDurationLong(stats.billableSeconds) },
    {
      label: "Unassigned",
      value: formatDurationLong(stats.unassignedSeconds),
      warn: stats.unassignedSeconds > 0,
    },
    {
      label: "Needs Review",
      value: String(stats.needsReviewCount),
      warn: stats.needsReviewCount > 0,
    },
    { label: "Top Project", value: topProject?.projectName ?? "—", color: topProject?.color },
  ];

  return (
    <div className="summary-cards five">
      {cards.map((c) => (
        <div key={c.label} className="summary-card">
          <div className={`card-value ${c.warn ? "warn" : ""}`} style={c.color ? { color: c.color } : undefined}>
            {c.value}
          </div>
          <div className="card-label">{c.label}</div>
        </div>
      ))}
    </div>
  );
}
