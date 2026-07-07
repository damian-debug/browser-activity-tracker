import type { DomainSummary } from "../../shared/types";
import { formatDuration } from "../../shared/utils";

interface Props {
  domains: DomainSummary[];
  totalSeconds: number;
}

export function DomainTable({ domains, totalSeconds }: Props) {
  if (domains.length === 0) {
    return <div className="empty-state">No domains tracked in this period.</div>;
  }

  return (
    <table className="data-table">
      <thead>
        <tr>
          <th>Domain</th>
          <th className="col-right">Time</th>
          <th className="col-right">Share</th>
          <th className="col-right">Sessions</th>
        </tr>
      </thead>
      <tbody>
        {domains.map((d) => {
          const pct = totalSeconds > 0 ? Math.round((d.totalSeconds / totalSeconds) * 100) : 0;
          return (
            <tr key={d.domain}>
              <td>
                <div className="domain-cell">
                  {d.service && <span className="service-tag">{d.service}</span>}
                  <span>{d.domain}</span>
                </div>
              </td>
              <td className="col-right mono">{formatDuration(d.totalSeconds)}</td>
              <td className="col-right">
                <div className="pct-cell">
                  <div className="pct-bar" style={{ width: `${pct}%` }} />
                  <span>{pct}%</span>
                </div>
              </td>
              <td className="col-right mono">{d.sessionCount}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}
