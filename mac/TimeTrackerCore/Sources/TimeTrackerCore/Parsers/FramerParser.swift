import Foundation

/// Handles the Framer editor and Framer-hosted sites:
///   https://framer.com/projects/{Name}--{projectId}
///   https://framer.com/projects/{Name}--{projectId}-{suffix}?node={nodeId}
///   https://framer.com/projects/{projectId}
///   https://{site}.framer.app/{page}           (also .framer.website)
///
/// Shapes taken from real sessions rather than documentation. Two things
/// matter about the editor:
///  - The tab title is only ever "{Name} – Framer", whichever page is open, so
///    the URL is the only place a location within the project shows up.
///  - Selecting something appends `?node=` and a short suffix to the project
///    segment at the same moment. Without this parser each change looked like
///    a different page and split the session; the stable id keeps it whole.
public struct FramerParser: URLParser {
    public init() {}

    private static let siteHosts = [".framer.app", ".framer.website"]

    public func parse(_ url: String) -> ParsedEntity? {
        guard let components = URLComponents(string: url),
              let host = components.host?.lowercased()
        else { return nil }

        if host == "framer.com" || host == "www.framer.com" {
            return editor(components, url: url)
        }
        if let suffix = Self.siteHosts.first(where: { host.hasSuffix($0) }) {
            let site = String(host.dropLast(suffix.count))
            guard !site.isEmpty, !site.contains(".") else { return nil }
            let page = components.path.isEmpty ? "/" : components.path
            return ParsedEntity(
                service: "framer", entityId: site, entityName: site,
                subEntityId: page, subEntityIsPage: true
            )
        }
        return nil
    }

    private func editor(_ components: URLComponents, url: String) -> ParsedEntity? {
        // ["", "projects", "Daniel-Framer-Claass--FC91PjIN9PCSOTMJzDXU-5ODEx"]
        let segments = components.path.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count >= 3, segments[1] == "projects" else { return nil }

        let raw = String(segments[2]).removingPercentEncoding ?? String(segments[2])
        var name: String?
        var rest = raw
        if let separator = raw.range(of: "--", options: .backwards) {
            let slug = raw[..<separator.lowerBound]
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespaces)
            name = slug.isEmpty ? nil : slug
            rest = String(raw[separator.upperBound...])
        }

        // The id is what comes before any suffix. Real ids are long random
        // strings; the length floor keeps list pages like /projects/folder
        // from being mistaken for a project.
        let id = String(rest.split(separator: "-").first ?? "")
        guard id.count >= 12, id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }

        let node = URLish.queryValue(url, name: "node")
        return ParsedEntity(
            service: "framer", entityId: id, entityName: name,
            subEntityId: node?.isEmpty == false ? node : nil
        )
    }
}
