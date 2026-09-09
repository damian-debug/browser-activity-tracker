import Foundation

/// One observation of what the user is doing right now. Replaces the
/// extension's "active tab" as the unit the tracker reasons about.
///
/// Only `bundleID`/`appName` are always populated; the rest depend on which
/// permissions have been granted, so every consumer must degrade gracefully.
public struct ActivitySnapshot: Hashable, Sendable, Codable {
    public var bundleID: String
    public var appName: String
    public var windowTitle: String?      // Accessibility
    public var url: String?              // Automation (browsers only)
    public var documentPath: String?     // Accessibility (kAXDocumentAttribute)
    public var capturedAt: Date

    public init(
        bundleID: String,
        appName: String,
        windowTitle: String? = nil,
        url: String? = nil,
        documentPath: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.documentPath = documentPath
        self.capturedAt = capturedAt
    }

    public var domain: String? {
        url.flatMap(URLish.extractDomain)
    }

    public var parsed: ParsedEntity? {
        url.flatMap(ParserRegistry.parse)
    }

    /// Best available human-readable label for this activity.
    public var displayTitle: String {
        windowTitle ?? url ?? appName
    }
}
