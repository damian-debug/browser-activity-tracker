import Foundation

/// First parser to claim the URL wins. This is the extension point for new
/// services — add a `URLParser` and register it here.
public enum ParserRegistry {
    public static let parsers: [any URLParser] = [FigmaParser(), FramerParser(), BubbleParser(), ClaudeParser()]

    /// Services whose address moves as you work while the tab title stays put:
    /// a Figma or Framer tab is titled after the file, never the screen. For
    /// these, the only way to notice a new screen is to re-read the address.
    public static let servicesWithLocationInURL: Set<String> = ["figma", "framer"]

    public static func locationChangesWithoutTitle(_ url: String) -> Bool {
        guard let service = parse(url)?.service else { return false }
        return servicesWithLocationInURL.contains(service)
    }

    public static func parse(_ url: String) -> ParsedEntity? {
        for parser in parsers {
            if let result = parser.parse(url) { return result }
        }
        return nil
    }
}
