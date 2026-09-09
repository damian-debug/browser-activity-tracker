import Foundation

public enum Backup {
    /// Kept identical to the Chrome extension so its export files are valid
    /// input here — that compatibility IS the migration path.
    public static let format = "bat-backup"

    /// v3 was the extension's final schema. v4 adds native app fields.
    public static let schemaVersion = 4

    /// Sessions imported from a browser-only export: the extension never
    /// recorded which browser, so saying "Browser" is the honest answer rather
    /// than guessing a bundle id.
    public static let importedBrowserBundleID = "imported.browser"
    public static let importedBrowserAppName = "Browser"

    public struct Contents: Hashable, Sendable {
        public var settings: AppSettings
        public var projects: [Project]
        public var tags: [Tag]
        public var rules: [ProjectRule]
        public var sessions: [Session]

        public init(
            settings: AppSettings = .default,
            projects: [Project] = [],
            tags: [Tag] = [],
            rules: [ProjectRule] = [],
            sessions: [Session] = []
        ) {
            self.settings = settings
            self.projects = projects
            self.tags = tags
            self.rules = rules
            self.sessions = sessions
        }
    }

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case notJSON
        case notABackupFile
        case tooNew(Int)
        case malformed(String)

        public var description: String {
            switch self {
            case .notJSON:
                return "That file isn't valid JSON."
            case .notABackupFile:
                return "That isn't an Activity Tracker backup file."
            case .tooNew(let version):
                return "This backup (v\(version)) was made by a newer version of the app. Update first, then import it."
            case .malformed(let detail):
                return "This backup is damaged: \(detail)."
            }
        }
    }

    // ── Export ───────────────────────────────────────────────────────────

    public static func encode(_ contents: Contents, exportedAt: Date = Date()) throws -> Data {
        let file = BackupDTO.File(
            format: format,
            schemaVersion: schemaVersion,
            exportedAt: exportedAt.unixMillis,
            settings: .init(
                idleThresholdSeconds: contents.settings.idleThresholdSeconds,
                reviewConfidenceThreshold: contents.settings.reviewConfidenceThreshold,
                excludedDomains: contents.settings.excludedDomains,
                excludedAppBundleIDs: contents.settings.excludedAppBundleIDs,
                minimumSessionSeconds: contents.settings.minimumSessionSeconds,
                maximumCreditedGapSeconds: contents.settings.maximumCreditedGapSeconds
            ),
            projects: contents.projects.map(dto),
            tags: contents.tags.map(dto),
            rules: contents.rules.map(dto),
            sessions: contents.sessions.map(dto)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    // ── Import ───────────────────────────────────────────────────────────

    public static func decode(_ data: Data) -> Result<Contents, ValidationError> {
        // Read the envelope first so we can give a precise reason for refusing,
        // rather than a generic decoding failure.
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.notJSON)
        }
        guard object["format"] as? String == format else {
            return .failure(.notABackupFile)
        }
        guard let version = object["schemaVersion"] as? Int else {
            return .failure(.notABackupFile)
        }
        // Older files are welcome; newer ones we cannot be trusted to read.
        guard version <= schemaVersion else {
            return .failure(.tooNew(version))
        }

        let file: BackupDTO.File
        do {
            file = try JSONDecoder().decode(BackupDTO.File.self, from: data)
        } catch {
            return .failure(.malformed(describe(error)))
        }

        guard file.projects.allSatisfy({ !$0.id.isEmpty }),
              file.tags.allSatisfy({ !$0.id.isEmpty }),
              file.rules.allSatisfy({ !$0.id.isEmpty }),
              file.sessions.allSatisfy({ !$0.id.isEmpty })
        else {
            return .failure(.malformed("some records have no id"))
        }

        return .success(Contents(
            settings: domain(file.settings),
            projects: file.projects.map(domain),
            tags: file.tags.map(domain),
            rules: file.rules.compactMap(domain),
            sessions: file.sessions.map(domain)
        ))
    }

    private static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return "\(error)" }
        switch error {
        case .keyNotFound(let key, _): return "missing field '\(key.stringValue)'"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? ctx.debugDescription : "bad value at '\(path)'"
        case .dataCorrupted(let ctx): return ctx.debugDescription
        @unknown default: return "\(error)"
        }
    }
}

// ── Mapping ──────────────────────────────────────────────────────────────

private extension Backup {
    static func dto(_ p: Project) -> BackupDTO.Project {
        .init(
            id: p.id, name: p.name, clientName: p.clientName, color: p.color,
            defaultBillable: p.defaultBillable, archived: p.archived,
            isFavourite: p.isFavourite, sortOrder: p.sortOrder, parentId: p.parentId,
            createdAt: p.createdAt.unixMillis, updatedAt: p.updatedAt.unixMillis
        )
    }

    static func dto(_ t: Tag) -> BackupDTO.Tag {
        .init(id: t.id, name: t.name, color: t.color,
              createdAt: t.createdAt.unixMillis, updatedAt: t.updatedAt.unixMillis)
    }

    static func dto(_ r: ProjectRule) -> BackupDTO.Rule {
        .init(
            id: r.id, projectId: r.projectId, featureId: r.featureId, name: r.name,
            type: r.type.rawValue, value: r.value, queryParamName: r.queryParamName,
            priority: r.priority, enabled: r.enabled,
            defaultTagIds: r.defaultTagIds, defaultBillable: r.defaultBillable,
            createdAt: r.createdAt.unixMillis, updatedAt: r.updatedAt.unixMillis
        )
    }

    static func dto(_ s: Session) -> BackupDTO.Session {
        .init(
            id: s.id, appBundleID: s.appBundleID, appName: s.appName,
            windowTitle: s.windowTitle, documentPath: s.documentPath,
            gitBranch: s.gitBranch, countedWhileAway: s.countedWhileAway,
            url: s.url, domain: s.domain, title: s.title,
            service: s.service, detectedEntityId: s.detectedEntityId,
            detectedEntityName: s.detectedEntityName,
            projectId: s.projectId, projectName: s.projectName,
            featureId: s.featureId, featureName: s.featureName,
            assignmentSource: s.assignmentSource.rawValue,
            assignmentConfidence: s.assignmentConfidence,
            matchedRuleId: s.matchedRuleId, tagIds: s.tagIds, notes: s.notes,
            billable: s.billable, reviewed: s.reviewed,
            startTime: s.startTime.unixMillis, endTime: s.endTime.unixMillis,
            durationSeconds: s.durationSeconds,
            createdAt: s.createdAt.unixMillis, updatedAt: s.updatedAt.unixMillis
        )
    }

    static func domain(_ s: BackupDTO.Settings) -> AppSettings {
        let d = AppSettings.default
        return AppSettings(
            idleThresholdSeconds: s.idleThresholdSeconds ?? d.idleThresholdSeconds,
            reviewConfidenceThreshold: s.reviewConfidenceThreshold ?? d.reviewConfidenceThreshold,
            excludedDomains: s.excludedDomains ?? d.excludedDomains,
            excludedAppBundleIDs: s.excludedAppBundleIDs ?? d.excludedAppBundleIDs,
            minimumSessionSeconds: s.minimumSessionSeconds ?? d.minimumSessionSeconds,
            maximumCreditedGapSeconds: s.maximumCreditedGapSeconds ?? d.maximumCreditedGapSeconds
        )
    }

    static func domain(_ p: BackupDTO.Project) -> Project {
        Project(
            id: p.id, name: p.name, clientName: p.clientName, color: p.color,
            defaultBillable: p.defaultBillable ?? false, archived: p.archived ?? false,
            parentId: p.parentId,
            isFavourite: p.isFavourite ?? false, sortOrder: p.sortOrder ?? 0,
            createdAt: Date(unixMillis: p.createdAt ?? 0),
            updatedAt: Date(unixMillis: p.updatedAt ?? 0)
        )
    }

    static func domain(_ t: BackupDTO.Tag) -> Tag {
        Tag(id: t.id, name: t.name, color: t.color,
            createdAt: Date(unixMillis: t.createdAt ?? 0),
            updatedAt: Date(unixMillis: t.updatedAt ?? 0))
    }

    /// Rules of an unknown type are dropped rather than guessed at — a rule
    /// that silently means something different would misattribute real time.
    static func domain(_ r: BackupDTO.Rule) -> ProjectRule? {
        guard let type = ProjectRuleType(rawValue: r.type) else { return nil }
        return ProjectRule(
            id: r.id, projectId: r.projectId, featureId: r.featureId,
            name: r.name, type: type, value: r.value,
            queryParamName: r.queryParamName, priority: r.priority ?? 0,
            enabled: r.enabled ?? true, defaultTagIds: r.defaultTagIds,
            defaultBillable: r.defaultBillable,
            createdAt: Date(unixMillis: r.createdAt ?? 0),
            updatedAt: Date(unixMillis: r.updatedAt ?? 0)
        )
    }

    static func domain(_ s: BackupDTO.Session) -> Session {
        Session(
            id: s.id,
            appBundleID: s.appBundleID ?? importedBrowserBundleID,
            appName: s.appName ?? importedBrowserAppName,
            windowTitle: s.windowTitle,
            documentPath: s.documentPath,
            gitBranch: s.gitBranch,
            url: s.url, domain: s.domain, title: s.title ?? "",
            service: s.service, detectedEntityId: s.detectedEntityId,
            detectedEntityName: s.detectedEntityName,
            projectId: s.projectId, projectName: s.projectName,
            featureId: s.featureId, featureName: s.featureName,
            assignmentSource: s.assignmentSource
                .flatMap(AssignmentSource.init(rawValue:)) ?? .unassigned,
            assignmentConfidence: s.assignmentConfidence ?? 0,
            matchedRuleId: s.matchedRuleId, tagIds: s.tagIds ?? [], notes: s.notes,
            billable: s.billable ?? false, reviewed: s.reviewed ?? false,
            countedWhileAway: s.countedWhileAway ?? false,
            startTime: Date(unixMillis: s.startTime),
            endTime: Date(unixMillis: s.endTime),
            durationSeconds: s.durationSeconds,
            createdAt: Date(unixMillis: s.createdAt ?? s.startTime),
            updatedAt: Date(unixMillis: s.updatedAt ?? s.endTime)
        )
    }
}
