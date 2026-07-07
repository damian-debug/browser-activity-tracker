import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from "recharts";
import type { DomainSummary } from "../../shared/types";
import { formatDuration } from "../../shared/utils";

const COLORS = ["#2563eb", "#3b82f6", "#60a5fa", "#93c5fd", "#bfdbfe"];

interface Props {
  domains: DomainSummary[];
}

function CustomTooltip({ active, payload }: { active?: boolean; payload?: Array<{ value: number; payload: DomainSummary }> }) {
  if (!active || !payload?.length) return null;
  const d = payload[0].payload;
  return (
    <div className="chart-tooltip">
      <div className="tooltip-domain">{d.domain}</div>
      <div className="tooltip-time">{formatDuration(d.totalSeconds)}</div>
      <div className="tooltip-meta">{d.sessionCount} session{d.sessionCount !== 1 ? "s" : ""}</div>
    </div>
  );
}

export function DomainChart({ domains }: Props) {
  const data = domains.slice(0, 10).map((d) => ({
    ...d,
    minutes: Math.round(d.totalSeconds / 60),
  }));

  if (data.length === 0) {
    return <div className="empty-chart">No data for this period</div>;
  }

  return (
    <ResponsiveContainer width="100%" height={220}>
      <BarChart data={data} layout="vertical" margin={{ left: 0, right: 40, top: 4, bottom: 4 }}>
        <XAxis type="number" unit="m" tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
        <YAxis
          type="category"
          dataKey="domain"
          width={140}
          tick={{ fontSize: 11 }}
          tickLine={false}
          axisLine={false}
        />
        <Tooltip content={<CustomTooltip />} cursor={{ fill: "#f0f4ff" }} />
        <Bar dataKey="minutes" radius={[0, 4, 4, 0]}>
          {data.map((_, i) => (
            <Cell key={i} fill={COLORS[Math.min(i, COLORS.length - 1)]} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}
