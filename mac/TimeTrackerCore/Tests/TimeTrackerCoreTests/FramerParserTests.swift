import Testing
import Foundation
@testable import TimeTrackerCore

// URLs below are the shapes recorded from real Framer use, not guesses.
private let named = "https://framer.com/projects/Daniel-Framer-Claass--FC91PjIN9PCSOTMJzDXU"
private let selected = "https://framer.com/projects/Daniel-Framer-Claass--FC91PjIN9PCSOTMJzDXU-5ODEx?node=R198OJlPy"
private let bare = "https://framer.com/projects/8lLustTMwnrm9yuei2vC"
private let site = "https://lively-benefits-431862.framer.app/newsroom/underwriting-edge-report-2026-launch"

private func chrome(_ url: String, title: String = "Daniel Framer Claass – Framer") -> ActivitySnapshot {
    ActivitySnapshot(bundleID: "com.google.Chrome", appName: "Google Chrome", windowTitle: title, url: url)
}

@Suite("Framer editor")
struct FramerEditorTests {
    @Test("a named project yields its id and a readable name")
    func named_() throws {
        let parsed = try #require(ParserRegistry.parse(named))
        #expect(parsed.service == "framer")
        #expect(parsed.entityId == "FC91PjIN9PCSOTMJzDXU")
        #expect(parsed.entityName == "Daniel Framer Claass")
        #expect(parsed.subEntityId == nil)
    }

    @Test("selecting something adds a node and a suffix; the project id is unchanged")
    func selection() throws {
        let parsed = try #require(ParserRegistry.parse(selected))
        #expect(parsed.entityId == "FC91PjIN9PCSOTMJzDXU")
        #expect(parsed.subEntityId == "R198OJlPy")
    }

    @Test("a project URL with no name still parses")
    func bareId() throws {
        let parsed = try #require(ParserRegistry.parse(bare))
        #expect(parsed.entityId == "8lLustTMwnrm9yuei2vC")
        #expect(parsed.entityName == nil)
    }

    @Test("project lists and other framer.com pages are not projects",
          arguments: [
            "https://framer.com/projects/folder/recent?team=bbaa5e63-9dfa-37e0-91ca-0381933df2e9",
            "https://framer.com/projects",
            "https://www.framer.com/community/gallery/",
            "https://framer.com/projects/new",
          ])
    func notProjects(url: String) {
        #expect(ParserRegistry.parse(url) == nil)
    }

    @Test("selecting things in one project no longer splits the session")
    func continuity() {
        // The real test split here: the URL gained ?node= and looked like a
        // different page.
        #expect(chrome(named).identity.continues(chrome(selected).identity))
        #expect(!chrome(named).identity.continues(chrome(bare, title: "Aoutive (copy) – Framer").identity))
    }

    @Test("the node becomes its own learning feature, alongside the project")
    func nodeIsAFeature() {
        let keys = Set(FeatureExtractor.features(for: chrome(selected)).map(\.key))
        #expect(keys.contains("entity:framer::FC91PjIN9PCSOTMJzDXU"))
        #expect(keys.contains("place:framer::FC91PjIN9PCSOTMJzDXU#R198OJlPy"))
    }
}

@Suite("Framer-hosted sites")
struct FramerSiteTests {
    @Test("the subdomain is the site and the path is the page")
    func site_() throws {
        let parsed = try #require(ParserRegistry.parse(site))
        #expect(parsed.entityId == "lively-benefits-431862")
        #expect(parsed.subEntityId == "/newsroom/underwriting-edge-report-2026-launch")
    }

    @Test("the older .framer.website domain too")
    func legacyDomain() throws {
        #expect(try #require(ParserRegistry.parse("https://acme.framer.website/")).entityId == "acme")
    }

    @Test("browsing a site's pages is one piece of work")
    func continuity() {
        let other = "https://lively-benefits-431862.framer.app/about"
        #expect(chrome(site, title: "A").identity.continues(chrome(other, title: "B").identity))
    }
}

@Suite("Rules from Framer sessions")
struct FramerRuleTests {
    func session(_ url: String) -> Session {
        let parsed = ParserRegistry.parse(url)
        return Session(
            appBundleID: "com.google.Chrome", appName: "Google Chrome",
            windowTitle: "Daniel Framer Claass – Framer", url: url,
            domain: URLish.extractDomain(url), title: "Daniel Framer Claass – Framer",
            service: parsed?.service, detectedEntityId: parsed?.entityId,
            detectedEntityName: parsed?.entityName,
            startTime: Date(), endTime: Date(), durationSeconds: 60
        )
    }

    @Test("the project is offered by id, so renaming it does not break the rule")
    func projectRule() throws {
        let suggestions = RuleSuggester.suggestions(for: session(named))
        let project = try #require(suggestions.first { $0.label.contains("Framer project") })
        #expect(project.conditions == [RuleCondition(type: .urlContains, value: "FC91PjIN9PCSOTMJzDXU")])

        // And it claims the project however its URL is dressed.
        let rule = ProjectRule(projectId: "p", name: "Daniel", conditions: project.conditions)
        for url in [named, selected] {
            #expect(RuleEngine.run(RuleBackfill.context(for: session(url)), rules: [rule]).projectId == "p")
        }
    }

    @Test("a selected screen is offered first, pinned by its node")
    func screenRule() throws {
        let suggestions = RuleSuggester.suggestions(for: session(selected))
        let screen = try #require(suggestions.first)
        #expect(screen.label.hasPrefix("This screen"))
        #expect(screen.conditions.contains(RuleCondition(type: .queryParamEquals, value: "R198OJlPy", queryParamName: "node")))

        let rule = ProjectRule(projectId: "p", name: "Pricing", conditions: screen.conditions)
        #expect(RuleEngine.run(RuleBackfill.context(for: session(selected)), rules: [rule]).projectId == "p")
        #expect(RuleEngine.run(RuleBackfill.context(for: session(named)), rules: [rule]).projectId == nil,
                "not the project as a whole")
    }

    @Test("no screen is offered when nothing is selected")
    func noScreen() {
        #expect(!RuleSuggester.suggestions(for: session(named)).contains { $0.label.hasPrefix("This screen") })
    }

    @Test("a site page is offered by path; the home page is not")
    func sitePage() {
        #expect(RuleSuggester.suggestions(for: session(site)).first?.label.hasPrefix("This screen") == true)
        #expect(!RuleSuggester.suggestions(for: session("https://acme.framer.app/")).contains { $0.label.hasPrefix("This screen") })
    }
}

@Suite("Screens are learned from finished sessions")
struct SessionPlaceFeatureTests {
    func session(url: String, service: String?, entity: String?) -> Session {
        Session(appBundleID: "com.google.Chrome", appName: "Google Chrome", windowTitle: "X", url: url,
                service: service, detectedEntityId: entity,
                startTime: Date(), endTime: Date(), durationSeconds: 60)
    }

    @Test("a finished Framer session teaches its screen, not just its project")
    func framer() {
        let keys = Set(FeatureExtractor.features(for: session(url: selected, service: "framer", entity: "FC91PjIN9PCSOTMJzDXU")).map(\.key))
        #expect(keys.contains("place:framer::FC91PjIN9PCSOTMJzDXU#R198OJlPy"))
    }

    @Test("and a Figma session its page — which never worked before")
    func figma() {
        let url = "https://www.figma.com/design/abc123/Acme?node-id=142-7"
        let keys = Set(FeatureExtractor.features(for: session(url: url, service: "figma", entity: "abc123")).map(\.key))
        #expect(keys.contains("place:figma::abc123#142-7"))
    }

    @Test("sessions recorded before a parser existed still gain their entity")
    func beforeParser() {
        let keys = Set(FeatureExtractor.features(for: session(url: selected, service: nil, entity: nil)).map(\.key))
        #expect(keys.contains("entity:framer::FC91PjIN9PCSOTMJzDXU"))
    }

    @Test("a URL that disagrees with the stored entity does not override it")
    func disagreement() {
        let keys = Set(FeatureExtractor.features(for: session(url: selected, service: "bubble", entity: "myapp")).map(\.key))
        #expect(keys.contains("entity:bubble::myapp"))
        #expect(!keys.contains { $0.hasPrefix("place:") })
    }
}
