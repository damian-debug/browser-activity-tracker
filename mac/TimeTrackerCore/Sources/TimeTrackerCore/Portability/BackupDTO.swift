import Foundation

// Wire format for backup files, kept deliberately separate from the domain
// models so serialisation concerns never leak into them — and so the v3/v4
// differences stay explicit and testable.
//
// v3 is the Chrome extension's format. We must read it: it is the entire
// migration path off the extension. Timestamps are unix milliseconds because
// that is what a JavaScript `number` date is.

enum BackupDTO {
    struct File: Codable {
        var format: String
        var schemaVersion: Int
        var exportedAt: Int64
        var settings: Settings
        var projects: [Project]
        var tags: [Tag]
        var rules: [Rule]
        var sessions: [Session]
    }

    struct Settings: Codable {
        var idleThresholdSeconds: Int?
        var reviewConfidenceThreshold: Int?
        var excludedDomains: [String]?
        var excludedAppBundleIDs: [String]?
        var minimumSessionSeconds: Int?
        var maximumCreditedGapSeconds: Int?
    }

    struct Project: Codable {
        var id: String
        var name: String
        var clientName: String?
        var color: String?
        var defaultBillable: Bool?
        var archived: Bool?
        var isFavourite: Bool?
        var sortOrder: Int?
        var createdAt: Int64?
        var updatedAt: Int64?
    }

    struct Tag: Codable {
        var id: String
        var name: String
        var color: String?
        var createdAt: Int64?
        var updatedAt: Int64?
    }

    struct Rule: Codable {
        var id: String
        var projectId: String
        var name: String
        var type: String
        var value: String
        var queryParamName: String?
        var priority: Int?
        var enabled: Bool?
        var defaultTagIds: [String]?
        var defaultBillable: Bool?
        var createdAt: Int64?
        var updatedAt: Int64?
    }

    struct Session: Codable {
        var id: String
        // v4 (native) fields — absent in extension exports.
        var appBundleID: String?
        var appName: String?
        var windowTitle: String?
        var documentPath: String?
        var countedWhileAway: Bool?
        // v3 fields.
        var url: String?
        var domain: String?
        var title: String?
        var service: String?
        var detectedEntityId: String?
        var detectedEntityName: String?
        var projectId: String?
        var projectName: String?
        var assignmentSource: String?
        var assignmentConfidence: Int?
        var matchedRuleId: String?
        var tagIds: [String]?
        var notes: String?
        var billable: Bool?
        var reviewed: Bool?
        var startTime: Int64
        var endTime: Int64
        var durationSeconds: Int
        var createdAt: Int64?
        var updatedAt: Int64?
    }
}
