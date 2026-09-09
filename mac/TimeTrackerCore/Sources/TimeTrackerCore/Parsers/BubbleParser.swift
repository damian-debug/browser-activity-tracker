import Foundation

/// Handles:
///   https://{appName}.bubbleapps.io/...              (published app)
///   https://{appName}.bubbleapps.io/version-test/... (test version)
///   https://bubble.io/page?name=...&id={appId}       (editor)
public struct BubbleParser: URLParser {
    public init() {}

    public func parse(_ url: String) -> ParsedEntity? {
        guard let components = URLComponents(string: url),
              let host = components.host
        else { return nil }

        // Editor
        if host == "bubble.io" && components.path.hasPrefix("/page") {
            guard let appId = URLish.queryValue(url, name: "id"), !appId.isEmpty else { return nil }
            return ParsedEntity(service: "bubble", entityId: appId, entityName: nil)
        }

        // Published / test app
        let suffix = ".bubbleapps.io"
        if host.hasSuffix(suffix) {
            let subdomain = String(host.dropLast(suffix.count))
            guard !subdomain.isEmpty else { return nil }
            return ParsedEntity(service: "bubble", entityId: subdomain, entityName: subdomain)
        }

        return nil
    }
}
