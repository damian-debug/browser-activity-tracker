import Foundation

public struct Project: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var clientName: String?
    public var color: String?
    public var defaultBillable: Bool
    public var archived: Bool

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
        self.isFavourite = isFavourite
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
