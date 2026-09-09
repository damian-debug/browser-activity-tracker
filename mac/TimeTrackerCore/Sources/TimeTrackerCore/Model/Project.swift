import Foundation

public struct Project: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var clientName: String?
    public var color: String?
    public var defaultBillable: Bool
    public var archived: Bool

    /// The project this is a feature of, or nil for a top-level project.
    ///
    /// Two levels, deliberately: a feature never has features of its own. That
    /// keeps every picker a list rather than a tree, and every report's
    /// roll-up unambiguous.
    public var parentId: String?

    // Native additions: back the menu bar favourites list.
    public var isFavourite: Bool
    public var sortOrder: Int

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        clientName: String? = nil,
        color: String? = nil,
        defaultBillable: Bool = false,
        archived: Bool = false,
        parentId: String? = nil,
        isFavourite: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.clientName = clientName
        self.color = color
        self.defaultBillable = defaultBillable
        self.archived = archived
        self.parentId = parentId
        self.isFavourite = isFavourite
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isFeature: Bool { parentId != nil }
}

public extension Array where Element == Project {
    /// Top-level projects only.
    var topLevel: [Project] { filter { !$0.isFeature } }

    /// Features belonging to one project, in display order.
    func features(of projectId: String) -> [Project] {
        filter { $0.parentId == projectId }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }
}
