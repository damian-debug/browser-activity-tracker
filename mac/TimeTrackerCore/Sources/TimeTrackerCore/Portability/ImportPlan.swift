import Foundation

public enum ImportMode: String, CaseIterable, Sendable {
    /// Combine with what's already here; on a clash the newer record wins.
    case merge
    /// Wipe local data and load the backup exactly as it is.
    case replace
}

public struct ImportPlan: Hashable, Sendable {
    public var mode: ImportMode
    public var projects: [Project]
    public var tags: [Tag]
    public var rules: [ProjectRule]
    public var sessions: [Session]
    /// Records skipped because the local copy was newer (merge only).
    public var skipped: Int
    public var settings: AppSettings?

    public var isEmpty: Bool {
        projects.isEmpty && tags.isEmpty && rules.isEmpty && sessions.isEmpty
    }
}

protocol Timestamped: Identifiable where ID == String {
    var updatedAt: Date { get }
}

extension Project: Timestamped {}
extension Tag: Timestamped {}
extension ProjectRule: Timestamped {}
extension Session: Timestamped {}

public extension Backup {
    /// Decide what a restore would actually change, without touching the store.
    ///
    /// Merge resolves clashes by `updatedAt`, newest wins, ties going to the
    /// local copy. That makes it idempotent and order-independent: importing
    /// the same file twice is a no-op, and two machines can swap backups in
    /// either direction and converge.
    static func plan(
        _ contents: Contents,
        existing: Contents,
        mode: ImportMode
    ) -> ImportPlan {
        switch mode {
        case .replace:
            return ImportPlan(
                mode: .replace,
                projects: contents.projects,
                tags: contents.tags,
                rules: contents.rules,
                sessions: contents.sessions,
                skipped: 0,
                // Replacing adopts the backup's settings; merging keeps this
                // machine's, since they describe this machine.
                settings: contents.settings
            )

        case .merge:
            let projects = merged(contents.projects, existing.projects)
            let tags = merged(contents.tags, existing.tags)
            let rules = merged(contents.rules, existing.rules)
            let sessions = merged(contents.sessions, existing.sessions)
            return ImportPlan(
                mode: .merge,
                projects: projects.keep,
                tags: tags.keep,
                rules: rules.keep,
                sessions: sessions.keep,
                skipped: projects.skipped + tags.skipped + rules.skipped + sessions.skipped,
                settings: nil
            )
        }
    }

    private static func merged<T: Timestamped>(
        _ incoming: [T], _ existing: [T]
    ) -> (keep: [T], skipped: Int) {
        let localByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var keep: [T] = []
        var skipped = 0
        for record in incoming {
            if let local = localByID[record.id], local.updatedAt >= record.updatedAt {
                skipped += 1
            } else {
                keep.append(record)
            }
        }
        return (keep, skipped)
    }
}
