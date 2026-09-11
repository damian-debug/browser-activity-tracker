import Foundation

/// Sessions as a spreadsheet.
///
/// This is what replaced the extension's Google Sheets webhook: the same data,
/// exported on demand to a file you own, with no service in the middle.
public enum CSVExport {
    /// RFC 4180: quote only when the field contains a comma, quote or line
    /// break, and escape quotes by doubling them.
    public static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Text from the outside world — a window title, a URL, a name — can start
    /// with `=`, `+`, `-` or `@` and be run as a formula when the file is opened
    /// in Excel or Google Sheets. Sheets will even fetch a URL built from other
    /// cells, quietly sending the sheet's contents to whoever titled the page.
    /// A leading apostrophe makes it plain text, as OWASP advises. Applied only
    /// to text columns; durations, dates and numbers are never touched.
    public static func neutralized(_ value: String) -> String {
        guard let first = value.unicodeScalars.first,
              "=+-@\t\r".unicodeScalars.contains(first)
        else { return value }
        return "'" + value
    }

    static let header = [
        "Date", "Start", "End", "Duration (seconds)",
        "Project", "Feature", "Client", "Tags", "Billable", "Reviewed",
        "Source", "Confidence",
        "App", "Window Title", "Document", "Branch",
        "Domain", "Service", "Entity ID", "Entity Name", "URL",
        "Counted While Away", "Notes",
    ]

    public static func csv(
        sessions: [Session],
        projects: [Project],
        tags: [Tag],
        helpers: DateHelpers = .current
    ) -> String {
        let projectsById = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let tagsById = Dictionary(tags.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var rows = [header.map(escape).joined(separator: ",")]

        for session in sessions {
            let project = session.projectId.flatMap { projectsById[$0] }
            let fields: [String] = [
                // Local date, so a row lands on the day you actually worked it,
                // while the timestamps stay unambiguous in ISO 8601.
                helpers.dateString(for: session.startTime),
                formatter.string(from: session.startTime),
                formatter.string(from: session.endTime),
                String(session.durationSeconds),
                // projectId is the source of truth; projectName is only a
                // denormalised cache. Showing a stale name for time that is
                // actually unassigned would be misleading on an invoice.
                neutralized(session.projectId == nil
                    ? "Unassigned"
                    : (project?.name ?? session.projectName ?? "Unknown project")),
                neutralized(session.featureId == nil
                    ? ""
                    : (projectsById[session.featureId!]?.name ?? session.featureName ?? "")),
                neutralized(project?.clientName ?? ""),
                neutralized(session.tagIds.map { tagsById[$0]?.name ?? $0 }.joined(separator: ", ")),
                session.billable ? "yes" : "no",
                session.reviewed ? "yes" : "no",
                session.assignmentSource.rawValue,
                String(session.assignmentConfidence),
                neutralized(session.appName),
                neutralized(session.windowTitle ?? ""),
                neutralized(session.documentPath ?? ""),
                neutralized(session.gitBranch ?? ""),
                neutralized(session.domain ?? ""),
                neutralized(session.service ?? ""),
                neutralized(session.detectedEntityId ?? ""),
                neutralized(session.detectedEntityName ?? ""),
                neutralized(session.url ?? ""),
                session.countedWhileAway ? "yes" : "no",
                neutralized(session.notes ?? ""),
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }

        return rows.joined(separator: "\r\n") + "\r\n"
    }
}
