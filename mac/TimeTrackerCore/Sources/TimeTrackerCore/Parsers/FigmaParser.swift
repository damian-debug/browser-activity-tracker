import Foundation

/// Handles:
///   https://www.figma.com/file/{fileId}/{slug}
///   https://www.figma.com/design/{fileId}/{slug}
///   https://www.figma.com/proto/{fileId}/{slug}
///   https://www.figma.com/board/{fileId}/{slug}   (FigJam)
public struct FigmaParser: URLParser {
    private static let kinds: Set<String> = ["file", "design", "proto", "board"]

    public init() {}

    public func parse(_ url: String) -> ParsedEntity? {
        guard let components = URLComponents(string: url),
              let host = components.host,
              host.contains("figma.com")
        else { return nil }

        // ["", "design", "abc123", "My-File"]
        let segments = components.path.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count >= 3,
              Self.kinds.contains(String(segments[1])),
              !segments[2].isEmpty
        else { return nil }

        let fileId = String(segments[2])
        var name: String?
        if segments.count >= 4, !segments[3].isEmpty {
            let slug = String(segments[3])
            let decoded = slug.removingPercentEncoding ?? slug
            let spaced = decoded.replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespaces)
            name = spaced.isEmpty ? nil : spaced
        }

        return ParsedEntity(service: "figma", entityId: fileId, entityName: name)
    }
}
