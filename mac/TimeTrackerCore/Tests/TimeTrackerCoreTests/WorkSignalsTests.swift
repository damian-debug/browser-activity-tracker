import Testing
import Foundation
@testable import TimeTrackerCore

@Suite("Ticket identifiers")
struct TicketSignalTests {
    @Test("finds a Jira or Linear key in a URL")
    func fromURL() {
        #expect(WorkSignals.ticket(
            url: "https://linear.app/acme/issue/ACME-142/payment-integration", title: nil
        ) == "ACME-142")
        #expect(WorkSignals.ticket(
            url: "https://acme.atlassian.net/browse/PAY-77", title: nil
        ) == "PAY-77")
    }

    @Test("finds a key in a window title, which is where most tools put it")
    func fromTitle() {
        #expect(WorkSignals.ticket(
            url: nil, title: "ACME-142 Payment integration · Linear"
        ) == "ACME-142")
    }

    @Test("GitHub issues are qualified by repository, since the number alone is meaningless")
    func github() {
        #expect(WorkSignals.ticket(
            url: "https://github.com/acme/checkout/pull/482", title: nil
        ) == "checkout#482")
        #expect(WorkSignals.ticket(
            url: "https://github.com/acme/checkout/issues/13", title: nil
        ) == "checkout#13")
    }

    @Test("ordinary text is not mistaken for a ticket")
    func noFalsePositives() {
        #expect(WorkSignals.ticket(url: nil, title: "Inbox") == nil)
        #expect(WorkSignals.ticket(url: "https://example.com/", title: "Google Meet") == nil)
        // Lowercase and over-long prefixes are not ticket keys.
        #expect(WorkSignals.ticket(url: nil, title: "abc-123") == nil)
        #expect(WorkSignals.ticket(url: nil, title: "SOMETHINGLONG-1") == nil)
        #expect(WorkSignals.ticket(url: nil, title: nil) == nil)
    }
}

@Suite("Git branch")
struct GitBranchTests {
    /// Builds a throwaway repository-shaped directory on disk.
    func makeRepo(branch: String?, detached: Bool = false) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tt-\(UUID().uuidString)")
        let git = root.appendingPathComponent(".git")
        let source = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        let head: String
        if detached {
            head = "9f2b1c4e5a6d7f8091a2b3c4d5e6f7089a1b2c3d\n"
        } else {
            head = "ref: refs/heads/\(branch ?? "main")\n"
        }
        try head.write(to: git.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        return root
    }

    @Test("reads the checked-out branch from a file inside the repository")
    func readsBranch() throws {
        let repo = try makeRepo(branch: "feature/payment-integration")
        defer { try? FileManager.default.removeItem(at: repo) }

        let file = repo.appendingPathComponent("src/Checkout.swift").path
        #expect(WorkSignals.gitBranch(forFileAt: file) == "feature/payment-integration")
    }

    @Test("branches that name no feature are ignored")
    func ignoresTrunkBranches() throws {
        // Knowing you are on main says nothing about which feature this is, and
        // would otherwise become a strong signal pointing everywhere at once.
        for trunk in ["main", "master", "develop", "production"] {
            let repo = try makeRepo(branch: trunk)
            defer { try? FileManager.default.removeItem(at: repo) }
            let file = repo.appendingPathComponent("src/x.swift").path
            #expect(WorkSignals.gitBranch(forFileAt: file) == nil, "\(trunk) should be ignored")
        }
    }

    @Test("a detached HEAD yields nothing, since a commit hash is not a feature")
    func detachedHead() throws {
        let repo = try makeRepo(branch: nil, detached: true)
        defer { try? FileManager.default.removeItem(at: repo) }
        #expect(WorkSignals.gitBranch(forFileAt: repo.appendingPathComponent("src/x.swift").path) == nil)
    }

    @Test("a file outside any repository yields nothing, without walking to the root")
    func noRepository() {
        #expect(WorkSignals.gitBranch(forFileAt: "/tmp/definitely-not-a-repo-\(UUID())/x.txt") == nil)
    }

    @Test("the upward walk is bounded")
    func boundedWalk() throws {
        let repo = try makeRepo(branch: "feature/deep")
        defer { try? FileManager.default.removeItem(at: repo) }

        // Deeper than the search limit: give up rather than scan forever on
        // every sample.
        let deep = repo.appendingPathComponent(
            Array(repeating: "a", count: 20).joined(separator: "/")
        ).appendingPathComponent("file.swift").path
        #expect(WorkSignals.repositoryRoot(for: deep, maxDepth: 3) == nil)
    }
}

@Suite("Figma pages")
struct FigmaPlaceTests {
    @Test("a node id identifies the page within the file")
    func capturesNode() {
        let parsed = try! #require(ParserRegistry.parse(
            "https://www.figma.com/design/abc123/Acme?node-id=142-7"
        ))
        #expect(parsed.entityId == "abc123")
        #expect(parsed.subEntityId == "142-7")
    }

    @Test("a file with no node still parses")
    func withoutNode() {
        let parsed = try! #require(ParserRegistry.parse("https://www.figma.com/design/abc123/Acme"))
        #expect(parsed.subEntityId == nil)
    }

    @Test("the page becomes a feature distinct from the file")
    func placeIsItsOwnFeature() {
        let snapshot = ActivitySnapshot(
            bundleID: "com.google.Chrome", appName: "Google Chrome",
            windowTitle: "Acme", url: "https://www.figma.com/design/abc123/Acme?node-id=142-7"
        )
        let keys = Set(FeatureExtractor.features(for: snapshot).map(\.key))
        #expect(keys.contains("entity:figma::abc123"))
        #expect(keys.contains("place:figma::abc123#142-7"))
    }

    @Test("two pages of one file are different work")
    func pagesDiffer() {
        func place(_ node: String) -> String? {
            let snapshot = ActivitySnapshot(
                bundleID: "com.google.Chrome", appName: "Google Chrome",
                url: "https://www.figma.com/design/abc123/Acme?node-id=\(node)"
            )
            return FeatureExtractor.features(for: snapshot)
                .first { $0.kind == .place }?.value
        }
        #expect(place("142-7") != place("999-1"))
    }
}

@Suite("Work signals as learning features")
struct WorkSignalFeatureTests {
    @Test("a ticket in the title becomes a strong feature")
    func ticketFeature() {
        let snapshot = ActivitySnapshot(
            bundleID: "com.google.Chrome", appName: "Google Chrome",
            windowTitle: "ACME-142 Payment integration · Linear",
            url: "https://linear.app/acme/issue/ACME-142"
        )
        let features = FeatureExtractor.features(for: snapshot)
        let ticket = try! #require(features.first { $0.kind == .ticket })
        #expect(ticket.value == "ACME-142")
        #expect(ticket.kind.weight >= ActivityFeature.Kind.host.weight)
    }

    @Test("a branch becomes a feature, and survives onto the finished session")
    func branchFeature() {
        let snapshot = ActivitySnapshot(
            bundleID: "com.microsoft.VSCode", appName: "Code",
            windowTitle: "Checkout.swift", documentPath: "/repo/src/Checkout.swift",
            gitBranch: "feature/payments"
        )
        #expect(FeatureExtractor.features(for: snapshot).contains {
            $0.kind == .branch && $0.value == "feature/payments"
        })

        // And the same feature is recoverable from the stored session, or the
        // model would forget the strongest signal it had the moment work ended.
        let session = ActiveSession(snapshot: snapshot, now: Date())
            .finalized(at: Date().addingTimeInterval(600))
        let stored = try! #require(session)
        #expect(stored.gitBranch == "feature/payments")
        #expect(FeatureExtractor.features(for: stored).contains { $0.kind == .branch })
    }
}

@Suite("Claude conversations")
struct ClaudeParserTests {
    @Test("a conversation becomes its own entity")
    func conversation() {
        let parsed = try! #require(ParserRegistry.parse(
            "https://claude.ai/chat/f5ebd55f-2b26-47b8-bbcb-c08c15a70c0f"
        ))
        #expect(parsed.service == "claude")
        #expect(parsed.entityId == "f5ebd55f-2b26-47b8-bbcb-c08c15a70c0f")
    }

    @Test("a Claude Code session is an entity too")
    func codeSession() {
        let parsed = try! #require(ParserRegistry.parse(
            "https://claude.ai/epitaxy/local_f5ebd55f-2b26-47b8-bbcb-c08c15a70c0f"
        ))
        #expect(parsed.entityId == "local_f5ebd55f-2b26-47b8-bbcb-c08c15a70c0f")
    }

    @Test("two conversations are different work")
    func conversationsDiffer() {
        // The whole point: without this every conversation reports a window
        // title of "Claude" and looks like the same session.
        let a = ParserRegistry.parse("https://claude.ai/chat/aaaaaaaa-1111-2222-3333-444444444444")
        let b = ParserRegistry.parse("https://claude.ai/chat/bbbbbbbb-1111-2222-3333-444444444444")
        #expect(a?.entityId != b?.entityId)
    }

    @Test("index and landing pages are not conversations")
    func notEveryPage() {
        #expect(ParserRegistry.parse("https://claude.ai/") == nil)
        #expect(ParserRegistry.parse("https://claude.ai/new") == nil)
        #expect(ParserRegistry.parse("https://claude.ai/chat") == nil)
        #expect(ParserRegistry.parse("https://claude.ai/settings/profile") == nil)
    }

    @Test("navigating within one conversation keeps a single session")
    func continuity() {
        func snapshot(_ url: String) -> ActivitySnapshot {
            ActivitySnapshot(
                bundleID: "com.anthropic.claudefordesktop", appName: "Claude",
                windowTitle: "Payments refactor", url: url
            )
        }
        let base = snapshot("https://claude.ai/chat/f5ebd55f-2b26-47b8-bbcb-c08c15a70c0f")
        let scrolled = snapshot("https://claude.ai/chat/f5ebd55f-2b26-47b8-bbcb-c08c15a70c0f#msg-9")
        #expect(base.identity.continues(scrolled.identity))

        let other = snapshot("https://claude.ai/chat/aaaaaaaa-1111-2222-3333-444444444444")
        #expect(!base.identity.continues(other.identity))
    }

    @Test("a conversation title becomes learnable feature evidence")
    func titleIsEvidence() {
        let snapshot = ActivitySnapshot(
            bundleID: "com.anthropic.claudefordesktop", appName: "Claude",
            windowTitle: "Payment integration review",
            url: "https://claude.ai/chat/f5ebd55f-2b26-47b8-bbcb-c08c15a70c0f"
        )
        let keys = Set(FeatureExtractor.features(for: snapshot).map(\.key))
        #expect(keys.contains("entity:claude::f5ebd55f-2b26-47b8-bbcb-c08c15a70c0f"))
        #expect(keys.contains("title:payment"))
        #expect(keys.contains("title:integration"))
        // The app's own name must not become a title token, or every
        // conversation would share it.
        #expect(!keys.contains("title:claude"))
    }
}
