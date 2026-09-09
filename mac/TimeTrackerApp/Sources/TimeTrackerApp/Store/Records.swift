import Foundation
import GRDB
import TimeTrackerCore

// GRDB records are kept separate from the domain models so persistence
// concerns never leak into TimeTrackerCore. Each one converts both ways.

private let jsonEncoder = JSONEncoder()
private let jsonDecoder = JSONDecoder()

private func encodeIDs(_ ids: [String]?) -> String? {
    guard let ids else { return nil }
    return (try? jsonEncoder.encode(ids)).flatMap { String(data: $0, encoding: .utf8) }
}

private func decodeIDs(_ raw: String?) -> [String]? {
    guard let raw, let data = raw.data(using: .utf8) else { return nil }
    return try? jsonDecoder.decode([String].self, from: data)
}

struct ProjectRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "project"

    var id: String
    var name: String
    var clientName: String?
    var color: String?
    var defaultBillable: Bool
    var archived: Bool
    var isFavourite: Bool
    var sortOrder: Int
    var parentId: String?
    var createdAt: Double
    var updatedAt: Double

    init(_ p: Project) {
        id = p.id; name = p.name; clientName = p.clientName; color = p.color
        defaultBillable = p.defaultBillable; archived = p.archived
        isFavourite = p.isFavourite; sortOrder = p.sortOrder; parentId = p.parentId
        createdAt = p.createdAt.timeIntervalSince1970
        updatedAt = p.updatedAt.timeIntervalSince1970
    }

    var domain: Project {
        Project(
            id: id, name: name, clientName: clientName, color: color,
            defaultBillable: defaultBillable, archived: archived,
            parentId: parentId, isFavourite: isFavourite, sortOrder: sortOrder,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}

struct TagRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tag"

    var id: String
    var name: String
    var color: String?
    var createdAt: Double
    var updatedAt: Double

    init(_ t: Tag) {
        id = t.id; name = t.name; color = t.color
        createdAt = t.createdAt.timeIntervalSince1970
        updatedAt = t.updatedAt.timeIntervalSince1970
    }

    var domain: Tag {
        Tag(id: id, name: name, color: color,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt))
    }
}

struct RuleRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "projectRule"

    var id: String
    var projectId: String
    var featureId: String?
    var name: String
    var conditions: String?
    // Kept in step with the first condition so older readers, and any SQL run
    // by hand, still see something sensible.
    var type: String
    var value: String
    var queryParamName: String?
    var priority: Int
    var enabled: Bool
    var defaultTagIds: String?
    var defaultBillable: Bool?
    var createdAt: Double
    var updatedAt: Double

    init(_ r: ProjectRule) {
        id = r.id; projectId = r.projectId; featureId = r.featureId; name = r.name
        conditions = (try? JSONEncoder().encode(r.conditions))
            .map { String(decoding: $0, as: UTF8.self) }
        type = r.type.rawValue; value = r.value; queryParamName = r.queryParamName
        priority = r.priority; enabled = r.enabled
        defaultTagIds = encodeIDs(r.defaultTagIds)
        defaultBillable = r.defaultBillable
        createdAt = r.createdAt.timeIntervalSince1970
        updatedAt = r.updatedAt.timeIntervalSince1970
    }

    /// Returns nil for a rule this build cannot represent, rather than
    /// silently reinterpreting it as a different kind of rule.
    var domain: ProjectRule? {
        let decoded: [RuleCondition]?
        if let conditions, let data = conditions.data(using: .utf8) {
            decoded = try? JSONDecoder().decode([RuleCondition].self, from: data)
        } else {
            decoded = nil
        }

        let resolved: [RuleCondition]
        if let decoded, !decoded.isEmpty {
            resolved = decoded
        } else if let kind = ProjectRuleType(rawValue: type) {
            resolved = [RuleCondition(type: kind, value: value, queryParamName: queryParamName)]
        } else {
            return nil
        }

        return ProjectRule(
            id: id, projectId: projectId, featureId: featureId,
            name: name, conditions: resolved,
            priority: priority, enabled: enabled,
            defaultTagIds: decodeIDs(defaultTagIds), defaultBillable: defaultBillable,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}

struct SessionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "session"

    var id: String
    var appBundleID: String
    var appName: String
    var windowTitle: String?
    var documentPath: String?
    var gitBranch: String?
    var url: String?
    var domain: String?
    var title: String
    var service: String?
    var detectedEntityId: String?
    var detectedEntityName: String?
    var projectId: String?
    var projectName: String?
    var featureId: String?
    var featureName: String?
    var assignmentSource: String
    var assignmentConfidence: Int
    var matchedRuleId: String?
    var tagIds: String
    var notes: String?
    var billable: Bool
    var reviewed: Bool
    var countedWhileAway: Bool
    var startTime: Double
    var endTime: Double
    var durationSeconds: Int
    var createdAt: Double
    var updatedAt: Double

    init(_ s: Session) {
        id = s.id; appBundleID = s.appBundleID; appName = s.appName
        windowTitle = s.windowTitle; documentPath = s.documentPath
        gitBranch = s.gitBranch
        url = s.url; domain = s.domain; title = s.title
        service = s.service; detectedEntityId = s.detectedEntityId
        detectedEntityName = s.detectedEntityName
        projectId = s.projectId; projectName = s.projectName
        featureId = s.featureId; featureName = s.featureName
        assignmentSource = s.assignmentSource.rawValue
        assignmentConfidence = s.assignmentConfidence
        matchedRuleId = s.matchedRuleId
        tagIds = encodeIDs(s.tagIds) ?? "[]"
        notes = s.notes; billable = s.billable; reviewed = s.reviewed
        countedWhileAway = s.countedWhileAway
        startTime = s.startTime.timeIntervalSince1970
        endTime = s.endTime.timeIntervalSince1970
        durationSeconds = s.durationSeconds
        createdAt = s.createdAt.timeIntervalSince1970
        updatedAt = s.updatedAt.timeIntervalSince1970
    }

    var domainModel: Session {
        Session(
            id: id, appBundleID: appBundleID, appName: appName,
            windowTitle: windowTitle, documentPath: documentPath, gitBranch: gitBranch,
            url: url, domain: domain, title: title,
            service: service, detectedEntityId: detectedEntityId,
            detectedEntityName: detectedEntityName,
            projectId: projectId, projectName: projectName,
            featureId: featureId, featureName: featureName,
            assignmentSource: AssignmentSource(rawValue: assignmentSource) ?? .unassigned,
            assignmentConfidence: assignmentConfidence,
            matchedRuleId: matchedRuleId,
            tagIds: decodeIDs(tagIds) ?? [],
            notes: notes, billable: billable, reviewed: reviewed,
            countedWhileAway: countedWhileAway,
            startTime: Date(timeIntervalSince1970: startTime),
            endTime: Date(timeIntervalSince1970: endTime),
            durationSeconds: durationSeconds,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}

struct AppStateRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "appState"
    var key: String
    var value: String
}

struct FeatureAssociationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "featureAssociation"

    var feature: String
    var projectId: String
    var mass: Double
    var observations: Int
    var lastUpdated: Double

    init(_ a: FeatureAssociation) {
        feature = a.feature
        projectId = a.projectId
        mass = a.mass
        observations = a.observations
        lastUpdated = a.lastUpdated.timeIntervalSince1970
    }

    var domain: FeatureAssociation {
        FeatureAssociation(
            feature: feature, projectId: projectId, mass: mass,
            observations: observations,
            lastUpdated: Date(timeIntervalSince1970: lastUpdated)
        )
    }
}
