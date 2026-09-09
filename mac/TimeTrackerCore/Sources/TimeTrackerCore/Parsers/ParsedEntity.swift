import Foundation

/// What a URL *is*, as detected by a parser: a specific Figma file, a specific
/// Bubble app. Distinct from which project the time is billed to.
public struct ParsedEntity: Hashable, Sendable {
    public let service: String
    public let entityId: String
    public let entityName: String?

    /// A location *within* the entity — a Figma page or frame, say. This is
    /// what distinguishes "the KPI screens" from "the onboarding flow" inside
    /// one file, so it is evidence about which feature is being worked on.
    public let subEntityId: String?

    public init(
        service: String, entityId: String,
        entityName: String? = nil, subEntityId: String? = nil
    ) {
        self.service = service
        self.entityId = entityId
        self.entityName = entityName
        self.subEntityId = subEntityId
    }
}

public protocol URLParser: Sendable {
    func parse(_ url: String) -> ParsedEntity?
}
