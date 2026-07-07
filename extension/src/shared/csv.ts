import type { Project, Session, Tag } from "./types";
import { dateStringForTimestamp } from "./utils";

// RFC 4180: quote a field if it contains a comma, quote, or line break;
// escape quotes by doubling them.
export function csvEscape(value: string): string {
  if (/[",\n\r]/.test(value)) return '"' + value.replace(/"/g, '""') + '"';
  return value;
}

const HEADER = [
  "Date",
  "Start",
  "End",
  "Duration (seconds)",
  "Project",
  "Client",
  "Tags",
  "Billable",
  "Reviewed",
  "Source",
  "Confidence",
  "Domain",
  "Service",
  "Entity ID",
  "Entity Name",
  "Title",
  "URL",
  "Notes",
];

// Sessions → spreadsheet-ready CSV (replaces the old Sheets webhook export:
// paste/import the file into any spreadsheet or CRM).
export function sessionsToCsv(sessions: Session[], projects: Project[], tags: Tag[]): string {
  const projectById = new Map(projects.map((p) => [p.id, p]));
  const tagById = new Map(tags.map((t) => [t.id, t]));

  const rows = sessions.map((s) => {
    const project = s.projectId ? projectById.get(s.projectId) : undefined;
    const fields = [
      dateStringForTimestamp(s.startTime),
      new Date(s.startTime).toISOString(),
      new Date(s.endTime).toISOString(),
      String(s.durationSeconds),
      project?.name ?? s.projectName ?? "Unassigned",
      project?.clientName ?? "",
      s.tagIds.map((id) => tagById.get(id)?.name ?? id).join(", "),
      s.billable ? "yes" : "no",
      s.reviewed ? "yes" : "no",
      s.assignmentSource,
      String(s.assignmentConfidence),
      s.domain,
      s.service ?? "",
      s.detectedEntityId ?? "",
      s.detectedEntityName ?? "",
      s.title,
      s.url,
      s.notes ?? "",
    ];
    return fields.map(csvEscape).join(",");
  });

  return [HEADER.map(csvEscape).join(","), ...rows].join("\r\n") + "\r\n";
}
