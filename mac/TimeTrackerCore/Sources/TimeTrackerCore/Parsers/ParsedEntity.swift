import Foundation

/// What a URL *is*, as detected by a parser: a specific Figma file, a specific
/// Bubble app. Distinct from which project the time is billed to.
public struct ParsedEntity: Hashable, Sendable {
    public let service: String
    public let entityId: String
    public let entityName: String?

    public init(service: String, entityId: String, entityName: String? = nil) {
        self.service = service
        self.entityId = entityId
        self.entityName = entityName
    }
}

public protocol URLParser: Sendable {
    func parse(_ url: String) -> ParsedEntity?
}
