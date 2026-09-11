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

    /// Whether the location is a real page (a Bubble page, a page of a site)
    /// rather than just the current selection (a Framer node, a Figma frame).
    /// Leaving a page leaves its feature behind; changing selection does not.
    public let subEntityIsPage: Bool

    public init(
        service: String, entityId: String,
        entityName: String? = nil, subEntityId: String? = nil,
        subEntityIsPage: Bool = false
    ) {
        self.service = service
        self.entityId = entityId
        self.entityName = entityName
        self.subEntityId = subEntityId
        self.subEntityIsPage = subEntityIsPage
    }
}

public protocol URLParser: Sendable {
    func parse(_ url: String) -> ParsedEntity?
}
