import Testing
import Foundation
@testable import TimeTrackerCore

// The audit flagged WHATWG `URL` vs Swift `URLComponents` as the highest-risk
// surface in the port: they differ on percent-encoding, empty hosts and query
// semantics. Every one of these was a total function in TypeScript (try/catch
// returning null), so the Swift versions must never trap.

@Suite("URL helpers")
struct URLishTests {
    @Test("extractDomain strips www and lowercases nothing else")
    func extractDomain() {
        #expect(URLish.extractDomain("https://www.figma.com/design/abc") == "figma.com")
        #expect(URLish.extractDomain("https://bubble.io/page?id=x") == "bubble.io")
        #expect(URLish.extractDomain("https://app.example.co.uk/x") == "app.example.co.uk")
    }

    @Test("extractDomain returns nil for anything that isn't a URL with a host")
    func extractDomainTotality() {
        #expect(URLish.extractDomain("") == nil)
        #expect(URLish.extractDomain("example.com") == nil)        // no scheme, as in JS
        #expect(URLish.extractDomain("not a url at all") == nil)
        #expect(URLish.extractDomain("file:///Users/d/notes.txt") == nil)
        #expect(URLish.extractDomain("about:blank") == nil)
    }

    @Test("path reports / for a bare origin, matching JS")
    func pathNormalisation() {
        #expect(URLish.path("https://example.com") == "/")
        #expect(URLish.path("https://example.com/") == "/")
        #expect(URLish.path("https://example.com/a/b") == "/a/b")
    }

    @Test("path excludes the query string")
    func pathExcludesQuery() {
        #expect(URLish.path("https://example.com/a?b=/c") == "/a")
    }

    @Test("path decodes percent-encoding")
    func pathDecoding() {
        #expect(URLish.path("https://example.com/my%20file") == "/my file")
    }

    @Test("path returns nil for malformed input")
    func pathTotality() {
        #expect(URLish.path("") == nil)
        #expect(URLish.path("nonsense") == nil)
    }

    @Test("queryValue reads a named parameter")
    func queryValue() {
        #expect(URLish.queryValue("https://bubble.io/page?id=sampleapp&tab=Design", name: "id") == "sampleapp")
        #expect(URLish.queryValue("https://bubble.io/page?id=sampleapp&tab=Design", name: "tab") == "Design")
        #expect(URLish.queryValue("https://bubble.io/page?id=sampleapp", name: "missing") == nil)
    }

    @Test("queryValue decodes + as a space, as URLSearchParams does")
    func queryPlusDecoding() {
        #expect(URLish.queryValue("https://example.com/?q=hello+world", name: "q") == "hello world")
        #expect(URLish.queryValue("https://example.com/?q=hello%20world", name: "q") == "hello world")
    }

    @Test("queryValue returns nil rather than trapping on malformed input")
    func queryTotality() {
        #expect(URLish.queryValue("", name: "id") == nil)
        #expect(URLish.queryValue("nonsense", name: "id") == nil)
        #expect(URLish.queryValue("https://example.com/", name: "id") == nil)
    }

    @Test("truncate elides long URLs and drops the scheme")
    func truncate() {
        #expect(URLish.truncate("https://example.com/short") == "example.com/short")
        let long = "https://example.com/" + String(repeating: "a", count: 100)
        #expect(URLish.truncate(long, maxLength: 20).count == 21)  // 20 + ellipsis
        #expect(URLish.truncate("not a url", maxLength: 20) == "not a url")
    }
}

@Suite("Entity parsers")
struct ParserTests {
    @Test("figma: file, design, proto and board URLs all yield the file id")
    func figmaKinds() {
        for kind in ["file", "design", "proto", "board"] {
            let parsed = ParserRegistry.parse("https://www.figma.com/\(kind)/abc123/My-File")
            #expect(parsed?.service == "figma")
            #expect(parsed?.entityId == "abc123")
        }
    }

    @Test("figma: the slug becomes a readable name")
    func figmaName() {
        let parsed = ParserRegistry.parse("https://www.figma.com/design/abc123/Q1-Dashboard-Designs")
        #expect(parsed?.entityName == "Q1 Dashboard Designs")
    }

    @Test("figma: percent-encoded slugs are decoded")
    func figmaEncodedName() {
        let parsed = ParserRegistry.parse("https://www.figma.com/design/abc123/My%20File")
        #expect(parsed?.entityName == "My File")
    }

    @Test("figma: a file with no slug still parses, with no name")
    func figmaNoSlug() {
        let parsed = ParserRegistry.parse("https://www.figma.com/design/abc123")
        #expect(parsed?.entityId == "abc123")
        #expect(parsed?.entityName == nil)
    }

    @Test("figma: non-file pages are not entities")
    func figmaNonFile() {
        #expect(ParserRegistry.parse("https://www.figma.com/files/recent") == nil)
        #expect(ParserRegistry.parse("https://www.figma.com/") == nil)
    }

    @Test("bubble: the editor URL yields the app id from the id parameter")
    func bubbleEditor() {
        let parsed = ParserRegistry.parse("https://bubble.io/page?id=sampleapp&tab=Design")
        #expect(parsed?.service == "bubble")
        #expect(parsed?.entityId == "sampleapp")
    }

    @Test("bubble: a published app yields its subdomain")
    func bubblePublished() {
        let parsed = ParserRegistry.parse("https://sampleapp.bubbleapps.io/version-test/home")
        #expect(parsed?.service == "bubble")
        #expect(parsed?.entityId == "sampleapp")
        #expect(parsed?.entityName == "sampleapp")
    }

    @Test("bubble: the editor without an id is not an entity")
    func bubbleNoId() {
        #expect(ParserRegistry.parse("https://bubble.io/page") == nil)
        #expect(ParserRegistry.parse("https://bubble.io/home") == nil)
    }

    @Test("unknown sites and malformed URLs parse to nil, never trapping")
    func unknownAndMalformed() {
        #expect(ParserRegistry.parse("https://example.com/whatever") == nil)
        #expect(ParserRegistry.parse("") == nil)
        #expect(ParserRegistry.parse("nonsense") == nil)
    }
}
