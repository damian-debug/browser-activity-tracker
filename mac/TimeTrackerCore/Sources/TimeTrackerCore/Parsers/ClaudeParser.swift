import Foundation

/// Handles Claude conversations and Claude Code sessions.
///
///   https://claude.ai/chat/{conversationId}
///   https://claude.ai/epitaxy/{sessionId}
///
/// The desktop app is Electron and reports a window title of just "Claude",
/// so without this every conversation looks like the same work. The URL comes
/// from its web area rather than a browser.
public struct ClaudeParser: URLParser {
    public init() {}

    public func parse(_ url: String) -> ParsedEntity? {
        guard let components = URLComponents(string: url),
              let host = components.host,
              host == "claude.ai" || host.hasSuffix(".claude.ai")
        else { return nil }

        let segments = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard segments.count >= 2 else { return nil }

        let identifier = segments[segments.count - 1]
        // Landing and index pages are not conversations. Real identifiers are
        // uuid-shaped, so anything short or wordy is skipped rather than
        // creating an entity per navigation.
        guard identifier.count >= 12, identifier.contains("-") else { return nil }

        return ParsedEntity(service: "claude", entityId: identifier, entityName: nil)
    }
}
