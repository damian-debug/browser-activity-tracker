import { useState } from "react";
import { daysAgoDateString, todayDateString } from "../../shared/utils";

export type PresetRange = "today" | "yesterday" | "7d" | "30d" | "custom";

export interface DateRange {
  from: string;
  to: string;
  preset: PresetRange;
}

interface Props {
  value: DateRange;
  onChange: (range: DateRange) => void;
}

const PRESETS: { label: string; value: PresetRange }[] = [
  { label: "Today", value: "today" },
  { label: "Yesterday", value: "yesterday" },
  { label: "Last 7 days", value: "7d" },
  { label: "Last 30 days", value: "30d" },
  { label: "Custom", value: "custom" },
];

export function presetToRange(preset: PresetRange, customFrom?: string, customTo?: string): DateRange {
  const today = todayDateString();
  switch (preset) {
    case "today":
      return { from: today, to: today, preset };
    case "yesterday": {
      const y = daysAgoDateString(1);
      return { from: y, to: y, preset };
    }
    case "7d":
      return { from: daysAgoDateString(6), to: today, preset };
    case "30d":
      return { from: daysAgoDateString(29), to: today, preset };
    case "custom":
      return { from: customFrom ?? today, to: customTo ?? today, preset };
  }
}

export function DateFilter({ value, onChange }: Props) {
  const [customFrom, setCustomFrom] = useState(value.from);
  const [customTo, setCustomTo] = useState(value.to);

  const handlePreset = (preset: PresetRange) => {
    if (preset === "custom") {
      onChange(presetToRange("custom", customFrom, customTo));
    } else {
      onChange(presetToRange(preset));
    }
  };

  const handleCustomApply = () => {
    onChange({ from: customFrom, to: customTo, preset: "custom" });
  };

  return (
    <div className="date-filter">
      <div className="preset-tabs">
        {PRESETS.map((p) => (
          <button
            key={p.value}
            className={`preset-tab ${value.preset === p.value ? "active" : ""}`}
            onClick={() => handlePreset(p.value)}
          >
            {p.label}
          </button>
        ))}
      </div>
      {value.preset === "custom" && (
        <div className="custom-range">
          <input
            type="date"
            value={customFrom}
            max={customTo}
            onChange={(e) => setCustomFrom(e.target.value)}
          />
          <span>–</span>
          <input
            type="date"
            value={customTo}
            min={customFrom}
            max={todayDateString()}
            onChange={(e) => setCustomTo(e.target.value)}
          />
          <button className="btn-apply" onClick={handleCustomApply}>
            Apply
          </button>
        </div>
      )}
    </div>
  );
}
