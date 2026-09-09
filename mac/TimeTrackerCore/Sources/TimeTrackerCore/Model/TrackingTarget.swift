import Foundation

/// What the current session is "about". Two consecutive snapshots resolving to
/// an equal target continue the same session; a different target ends it and
/// starts a new one.
///
/// This is the generalisation of the extension's `isSameTarget`, which existed
/// to stop SPA URL churn fragmenting one Figma file into dozens of slivers. The
/// same problem exists natively — a code editor rewrites its title on every
/// file switch — so the concept earns its keep at every level.
///
/// Cases are ordered strongest (most specific) to weakest; resolution picks the
/// strongest identity the available signals support.
public enum TrackingTarget: Hashable, Sendable, Codable {
    case entity(service: String, id: String)
    case document(bundleID: String, path: String)
    case webPage(url: String)
    case window(bundleID: String, title: String)
    case app(bundleID: String)

    public static func resolve(_ snapshot: ActivitySnapshot) -> TrackingTarget {
        // A parser-detected entity is the strongest signal: it survives URL
        // churn within one Figma file or Bubble app.
        if let parsed = snapshot.parsed {
            return .entity(service: parsed.service, id: parsed.entityId)
        }
        // A document path is stable across window-title edits (dirty markers,
        // line numbers) and identifies the actual artefact being worked on.
        if let path = snapshot.documentPath, !path.isEmpty {
            return .document(bundleID: snapshot.bundleID, path: path)
        }
        if let url = snapshot.url, !url.isEmpty {
            return .webPage(url: url)
        }
        if let title = snapshot.windowTitle, !title.isEmpty {
            return .window(bundleID: snapshot.bundleID, title: title)
        }
        return .app(bundleID: snapshot.bundleID)
    }

    /// Whether `snapshot` continues the session currently on `self`.
    public func matches(_ snapshot: ActivitySnapshot) -> Bool {
        self == TrackingTarget.resolve(snapshot)
    }
}
