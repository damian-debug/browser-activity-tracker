import type { EntitySummary } from "../../shared/types";
import { formatDuration } from "../../shared/utils";

interface Props {
  entities: EntitySummary[];
}

// Detected entities: Figma files, Bubble apps — what the parsers identified,
// independent of which Project the time was assigned to.
export function EntityTable({ entities }: Props) {
  if (entities.length === 0) {
    return (
      <div className="empty-state">
        No detected entities. Entities are recognized on Figma and Bubble.
      </div>
    );
  }

  return (
    <table className="data-table">
      <thead>
        <tr>
          <th>Service</th>
          <th>Entity</th>
          <th className="col-right">Time</th>
          <th className="col-right">Sessions</th>
          <th>Last Active</th>
        </tr>
      </thead>
      <tbody>
        {entities.map((e) => (
          <tr key={`${e.service}::${e.detectedEntityId}`}>
            <td><span className="service-tag">{e.service}</span></td>
            <td>
              <div className="project-cell">
                <span className="project-name">{e.detectedEntityName ?? e.detectedEntityId}</span>
                {e.detectedEntityName && <span className="project-id">{e.detectedEntityId}</span>}
              </div>
            </td>
            <td className="col-right mono">{formatDuration(e.totalSeconds)}</td>
            <td className="col-right mono">{e.sessionCount}</td>
            <td className="col-muted">
              {new Date(e.lastSeen).toLocaleDateString(undefined, {
                month: "short", day: "numeric", hour: "2-digit", minute: "2-digit",
              })}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
