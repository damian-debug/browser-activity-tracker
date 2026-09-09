import Testing
import Foundation
import TimeTrackerCore
@testable import TimeTrackerApp

// The real coordinator against a real SQLite store — no fakes on either side.
// This is the closest thing to running the app that can be checked headlessly,
// and it exercises exactly the path the app uses.

private let start = Date(timeIntervalSince1970: 1_700_000_000)

private func figmaWork() -> ActivitySnapshot {
    ActivitySnapshot(
        bundleID: "com.figma.Desktop", appName: "Figma",
        windowTitle: "KPI Screens", documentPath: "/Users/d/Projects/acme/kpi.fig"
    )
}

@Suite("End to end: teaching the tracker")
struct EndToEndLearningTests {
    func freshStore() throws -> TrackerStore {
        let store = try TrackerStore()
        try store.save(Project(id: "acme", name: "Acme Corp"))
        try store.save(Project(id: "internal", name: "Internal"))
        return store
    }

    /// Work on something, tell the tracker what it was, let the session close.
    func teach(
        _ coordinator: ActivityCoordinator,
        _ snapshot: ActivitySnapshot,
        project: Project,
        at when: Date
    ) async {
        await coordinator.observe(snapshot, now: when)
        await coordinator.reassignCurrentSession(
            to: Assignment(
                projectId: project.id, projectName: project.name,
                assignmentSource: .manualPopup, assignmentConfidence: Confidence.manual
            ),
            now: when
        )
        await coordinator.endSession(at: when.addingTimeInterval(1800))
    }

    @Test("after a week of being told, it stops asking")
    func learnsThenSuggests() async throws {
        let store = try freshStore()
        let acme = try #require(try store.projects().first { $0.id == "acme" })
        let coordinator = ActivityCoordinator(dependencies: store)

        // Seven days of half-hour sessions, each assigned by hand.
        for day in 0..<7 {
            await teach(
                coordinator, figmaWork(), project: acme,
                at: start.addingTimeInterval(Double(day) * 86_400)
            )
        }

        #expect(try store.learningRowCount() > 0, "assignments should have been learned")

        // The eighth day: same work, nothing said.
        let eighthDay = start.addingTimeInterval(7 * 86_400)
        await coordinator.observe(figmaWork(), now: eighthDay)

        let status = await coordinator.status(now: eighthDay)
        #expect(status.projectId == "acme")
        #expect(status.assignmentSource == .suggested)
        #expect((status.assignmentConfidence ?? 0) >= AppSettings.default.learnedMinimumConfidence)
    }

    @Test("the suggestion can say why, naming real evidence")
    func suggestionExplainsItself() async throws {
        let store = try freshStore()
        let acme = try #require(try store.projects().first { $0.id == "acme" })
        let coordinator = ActivityCoordinator(dependencies: store)

        for day in 0..<7 {
            await teach(coordinator, figmaWork(), project: acme,
                        at: start.addingTimeInterval(Double(day) * 86_400))
        }
        await coordinator.observe(figmaWork(), now: start.addingTimeInterval(7 * 86_400))

        let suggestion = try #require(await coordinator.suggestionForCurrentSession())
        let text = suggestion.explanation(
            projectName: "Acme Corp", now: start.addingTimeInterval(7 * 86_400)
        )
        #expect(text.contains("Acme Corp"))
        // The document folder is the signal that generalises here, so it should
        // be what the explanation leads with.
        #expect(suggestion.evidence.first?.feature.kind == .document)
    }

    @Test("correcting it changes what it suggests next time")
    func correctionChangesBehaviour() async throws {
        let store = try freshStore()
        let acme = try #require(try store.projects().first { $0.id == "acme" })
        let internalProject = try #require(try store.projects().first { $0.id == "internal" })
        let coordinator = ActivityCoordinator(dependencies: store)

        for day in 0..<7 {
            await teach(coordinator, figmaWork(), project: acme,
                        at: start.addingTimeInterval(Double(day) * 86_400))
        }

        // It now suggests Acme. Overrule it, repeatedly — the work moved.
        for day in 7..<20 {
            let when = start.addingTimeInterval(Double(day) * 86_400)
            await coordinator.observe(figmaWork(), now: when)
            await coordinator.reassignCurrentSession(
                to: Assignment(
                    projectId: internalProject.id, projectName: internalProject.name,
                    assignmentSource: .manualPopup, assignmentConfidence: Confidence.manual
                ),
                now: when
            )
            await coordinator.endSession(at: when.addingTimeInterval(1800))
        }

        let later = start.addingTimeInterval(20 * 86_400)
        await coordinator.observe(figmaWork(), now: later)

        let status = await coordinator.status(now: later)
        #expect(status.projectId == "internal", "being corrected must actually change its mind")
    }

    @Test("a tool used for everything is never confidently attributed")
    func sharedToolStaysUnassigned() async throws {
        let store = try freshStore()
        let acme = try #require(try store.projects().first { $0.id == "acme" })
        let internalProject = try #require(try store.projects().first { $0.id == "internal" })
        let coordinator = ActivityCoordinator(dependencies: store)

        // Slack, genuinely used for both projects, with nothing to tell them apart.
        let slack = ActivitySnapshot(
            bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", windowTitle: "Slack"
        )
        for day in 0..<20 {
            await teach(
                coordinator, slack,
                project: day.isMultiple(of: 2) ? acme : internalProject,
                at: start.addingTimeInterval(Double(day) * 86_400)
            )
        }

        let later = start.addingTimeInterval(20 * 86_400)
        await coordinator.observe(slack, now: later)

        let status = await coordinator.status(now: later)
        #expect(status.projectId == nil,
                "twenty ambiguous examples should produce honesty, not a coin flip")
    }

    @Test("it never learns from its own guesses")
    func noSelfReinforcement() async throws {
        let store = try freshStore()
        let acme = try #require(try store.projects().first { $0.id == "acme" })
        let coordinator = ActivityCoordinator(dependencies: store)

        for day in 0..<7 {
            await teach(coordinator, figmaWork(), project: acme,
                        at: start.addingTimeInterval(Double(day) * 86_400))
        }
        let afterTeaching = try store.learningRowCount()
        let massAfterTeaching = try store
            .loadAssociations(forFeatureKeys: ["document:/Users/d/Projects/acme"])
            .first?.mass ?? 0

        // Now let it run on its own suggestions for a fortnight, unchallenged.
        for day in 7..<21 {
            let when = start.addingTimeInterval(Double(day) * 86_400)
            await coordinator.observe(figmaWork(), now: when)
            await coordinator.endSession(at: when.addingTimeInterval(1800))
        }

        let row = try #require(try store
            .loadAssociations(forFeatureKeys: ["document:/Users/d/Projects/acme"]).first)

        #expect(try store.learningRowCount() == afterTeaching, "no new features invented")

        // Stored mass is untouched because nothing was written — which is the
        // point: a fortnight of its own guesses added exactly no evidence.
        #expect(row.mass == massAfterTeaching, "self-reinforcement would have grown this")

        // And because evidence is aged wherever it is read, the belief is
        // weaker now than when it was last taught, rather than compounding.
        let later = start.addingTimeInterval(21 * 86_400)
        #expect(LearnedIndex.default.decayedMass(row, now: later) < massAfterTeaching)
    }
}
