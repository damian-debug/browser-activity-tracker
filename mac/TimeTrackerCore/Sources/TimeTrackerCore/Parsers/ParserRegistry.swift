import Foundation

/// First parser to claim the URL wins. This is the extension point for new
/// services — add a `URLParser` and register it here.
public enum ParserRegistry {
    public static let parsers: [any URLParser] = [FigmaParser(), BubbleParser()]

    public static func parse(_ url: String) -> ParsedEntity? {
        for parser in parsers {
            if let result = parser.parse(url) { return result }
        }
        return nil
    }
}
