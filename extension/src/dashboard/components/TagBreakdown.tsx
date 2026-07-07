import type { DashboardStats } from "../../shared/types";
import { formatDuration } from "../../shared/utils";

interface Props {
  stats: DashboardStats;
}

export function TagBreakdown({ stats }: Props) {
  const max = stats.tagTotals[0]?.totalSeconds ?? 0;

  if (stats.tagTotals.length === 0) {
    return <div className="empty-state">No tagged time in this period.</div>;
  }

  return (
    <div className="tag-breakdown">
      {stats.tagTotals.map((t) => (
        <div key={t.tagId} className="tag-bar-row">
          <span className="tag-bar-name" style={t.color ? { color: t.color } : undefined}>
            {t.tagName}
          </span>
          <div className="tag-bar-track">
            <div
              className="tag-bar-fill"
              style={{
                width: `${max > 0 ? Math.max(2, (t.totalSeconds / max) * 100) : 0}%`,
                background: t.color ?? "#60a5fa",
              }}
            />
          </div>
          <span className="tag-bar-time">{formatDuration(t.totalSeconds)}</span>
        </div>
      ))}
    </div>
  );
}
