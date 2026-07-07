export function formatDuration(seconds: number): string {
  if (seconds < 60) return `${seconds}s`;
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0 && s > 0) return `${m}m ${s}s`;
  return `${m}m`;
}

export function formatDurationLong(seconds: number): string {
  if (seconds < 60) return `${seconds} sec`;
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h > 0 && m > 0) return `${h}h ${m}m`;
  if (h > 0) return `${h}h`;
  return `${m}m`;
}

export function extractDomain(url: string): string | null {
  try {
    const u = new URL(url);
    return u.hostname.replace(/^www\./, "");
  } catch {
    return null;
  }
}

export function todayDateString(): string {
  return new Date().toISOString().slice(0, 10);
}

export function dateStringForTimestamp(ts: number): string {
  return new Date(ts).toISOString().slice(0, 10);
}

export function startOfDayMs(dateStr: string): number {
  return new Date(dateStr + "T00:00:00").getTime();
}

export function endOfDayMs(dateStr: string): number {
  return new Date(dateStr + "T23:59:59.999").getTime();
}

export function daysAgoDateString(n: number): string {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d.toISOString().slice(0, 10);
}

export function truncateUrl(url: string, maxLen = 60): string {
  try {
    const u = new URL(url);
    const display = u.hostname + u.pathname;
    return display.length > maxLen ? display.slice(0, maxLen) + "…" : display;
  } catch {
    return url.length > maxLen ? url.slice(0, maxLen) + "…" : url;
  }
}
