import Foundation

/// A single piece of evidence about what an activity is.
///
/// Features are deliberately discrete strings so the whole model is a set of
/// counts you can read, print and argue with. That is the point: a suggestion
/// that cannot explain itself has no business assigning billable time.
public struct ActivityFeature: Hashable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case app          // app:com.figma.Desktop
        case entity       // entity:figma::abc123
        case document     // doc:/Users/d/Projects/acme
        case path         // path:app.example.com/project/acme
        case host         // host:figma.com
        case title        // title:acme

        /// How much one observation of this kind is worth.
        ///
        /// Mirrors the intuition already encoded in the hand-written rule
        /// confidence table: a specific file or app id is strong evidence, a
        /// whole domain is weak, and a single word from a window title is
        /// weaker still. Unlike that table, these only set the ceiling — how
        /// *consistently* a feature has pointed at one project decides the rest.
        public var weight: Double {
            switch self {
            case .entity: return 4.0
            case .document: return 3.0
            case .path: return 2.5
            case .host: return 1.5
            case .app: return 1.0
            case .title: return 0.4
            }
        }
    }

    public let kind: Kind
    public let value: String

    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }

    /// Stable storage key.
    public var key: String { "\(kind.rawValue):\(value)" }

    public static func parse(key: String) -> ActivityFeature? {
        guard let separator = key.firstIndex(of: ":") else { return nil }
        let rawKind = String(key[key.startIndex..<separator])
        let value = String(key[key.index(after: separator)...])
        guard let kind = Kind(rawValue: rawKind), !value.isEmpty else { return nil }
        return ActivityFeature(kind: kind, value: value)
    }

    /// Short human phrasing, for explaining a suggestion.
    public var describedSubject: String {
        switch kind {
        case .app: return "this app"
        case .entity: return value.replacingOccurrences(of: "::", with: " ")
        case .document: return value
        case .path: return value
        case .host: return value
        case .title: return "“\(value)” in the window title"
        }
    }
}

public enum FeatureExtractor {
    /// Window-title words that carry no signal about *which* project this is.
    /// Kept deliberately short — a token that appears everywhere ends up with
    /// low purity and contributes nothing anyway, so the maths does most of
    /// this work without a curated list.
    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "you", "your",
        "new", "tab", "untitled", "document", "window", "page", "home",
        "http", "https", "www", "com",
    ]

    public static func features(for snapshot: ActivitySnapshot) -> [ActivityFeature] {
        features(
            bundleID: snapshot.bundleID,
            appName: snapshot.appName,
            windowTitle: snapshot.windowTitle,
            url: snapshot.url,
            domain: snapshot.domain,
            documentPath: snapshot.documentPath,
            parsed: snapshot.parsed
        )
    }

    public static func features(for session: Session) -> [ActivityFeature] {
        let parsed: ParsedEntity?
        if let service = session.service, let id = session.detectedEntityId {
            parsed = ParsedEntity(service: service, entityId: id, entityName: session.detectedEntityName)
        } else {
            parsed = nil
        }
        return features(
            bundleID: session.appBundleID,
            appName: session.appName,
            windowTitle: session.windowTitle ?? session.title,
            url: session.url,
            domain: session.domain,
            documentPath: session.documentPath,
            parsed: parsed
        )
    }

    static func features(
        bundleID: String,
        appName: String,
        windowTitle: String?,
        url: String?,
        domain: String?,
        documentPath: String?,
        parsed: ParsedEntity?
    ) -> [ActivityFeature] {
        var features: [ActivityFeature] = []

        if !bundleID.isEmpty {
            features.append(ActivityFeature(kind: .app, value: bundleID))
        }

        if let parsed {
            features.append(ActivityFeature(
                kind: .entity, value: "\(parsed.service)::\(parsed.entityId)"
            ))
        }

        if let domain, !domain.isEmpty {
            features.append(ActivityFeature(kind: .host, value: domain))

            // Path prefixes at two depths. One segment catches
            // "app.example.com/acme"; two catches "…/project/acme". Deeper than
            // that is usually a specific page rather than a project.
            if let url, let path = URLish.path(url) {
                let segments = path.split(separator: "/").prefix(2)
                var accumulated = domain
                for segment in segments {
                    accumulated += "/\(segment)"
                    features.append(ActivityFeature(kind: .path, value: accumulated))
                }
            }
        }

        if let documentPath, !documentPath.isEmpty {
            features.append(contentsOf: documentFeatures(documentPath))
        }

        if let windowTitle {
            for token in titleTokens(windowTitle, appName: appName) {
                features.append(ActivityFeature(kind: .title, value: token))
            }
        }

        return features
    }

    /// Ancestor folders of an open document.
    ///
    /// The file itself is usually too specific to generalise — you rarely open
    /// the same file twice — while the folder it lives in is exactly the level
    /// a project lives at. So we record the enclosing directories rather than
    /// the file, at up to three depths.
    static func documentFeatures(_ path: String) -> [ActivityFeature] {
        let url = URL(fileURLWithPath: path)
        var directories: [String] = []
        var current = url.deletingLastPathComponent()

        while directories.count < 3, current.pathComponents.count > 2 {
            directories.append(current.path)
            current = current.deletingLastPathComponent()
        }
        return directories.map { ActivityFeature(kind: .document, value: $0) }
    }

    /// Tokens from a window title, with the noise stripped.
    ///
    /// Titles are the messiest signal available: they carry unsaved markers,
    /// notification counts, and the app's own name. The app name in particular
    /// must go, or it would double-count the app feature under a different kind.
    static func titleTokens(_ title: String, appName: String) -> [String] {
        let appTokens = Set(tokenize(appName))
        var seen = Set<String>()
        var tokens: [String] = []

        for token in tokenize(title) {
            guard !appTokens.contains(token), !stopWords.contains(token) else { continue }
            guard token.count >= 3, !token.allSatisfy(\.isNumber) else { continue }
            guard seen.insert(token).inserted else { continue }
            tokens.append(token)
            if tokens.count == 8 { break }
        }
        return tokens
    }

    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
