import Testing
import Foundation
@testable import TimeTrackerCore

private let base = Date(unixMillis: 1_700_000_000_000)

private func session(
    project: String? = "p1",
    title: String = "KPI Screens",
    tagIds: [String] = ["t1"],
    seconds: Int = 3600,
    away: Bool = false
) -> Session {
    Session(
        id: "s1", appBundleID: "com.figma.Desktop", appName: "Figma",
        windowTitle: title, documentPath: "/Users/d/Projects/acme/kpi.fig",
        url: nil, domain: nil, title: title,
        projectId: project, projectName: "Acme Corp",
        assignmentSource: .autoRule, assignmentConfidence: 85,
        tagIds: tagIds, billable: true, reviewed: true, countedWhileAway: away,
        startTime: base, endTime: base.addingTimeInterval(Double(seconds)),
        durationSeconds: seconds
    )
}

@Suite("CSV export")
struct CSVExportTests {
    let projects = [Project(id: "p1", name: "Acme Corp", clientName: "Acme, Inc.")]
    let tags = [Tag(id: "t1", name: "Design")]

    @Test("quotes only what needs quoting, doubling inner quotes")
    func escaping() {
        #expect(CSVExport.escape("plain") == "plain")
        #expect(CSVExport.escape("a,b") == "\"a,b\"")
        #expect(CSVExport.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVExport.escape("line\nbreak") == "\"line\nbreak\"")
    }

    @Test("emits a header and one row per session, with names resolved")
    func rows() {
        let csv = CSVExport.csv(sessions: [session()], projects: projects, tags: tags)
        let lines = csv.split(separator: "\r\n", omittingEmptySubsequences: true)
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("Date,Start,End,Duration (seconds),Project,Client"))
        #expect(lines[1].contains("Acme Corp"))
        #expect(lines[1].contains("\"Acme, Inc.\""))
        #expect(lines[1].contains("Design"))
        #expect(lines[1].contains("3600"))
    }

    @Test("carries the native columns the extension never had")
    func nativeColumns() {
        let csv = CSVExport.csv(sessions: [session()], projects: projects, tags: tags)
        #expect(csv.contains("App,Window Title,Document"))
        #expect(csv.contains("Figma"))
        #expect(csv.contains("/Users/d/Projects/acme/kpi.fig"))
    }

    @Test("away-time is marked, so it is never mistaken for desk work")
    func awayColumn() {
        let csv = CSVExport.csv(sessions: [session(away: true)], projects: projects, tags: tags)
        let row = csv.split(separator: "\r\n").last!
        #expect(row.contains("yes"))
        #expect(CSVExport.header.contains("Counted While Away"))
    }

    @Test("a title full of commas, quotes and newlines cannot break the row structure")
    func trickyTitle() {
        let tricky = session(title: "Board, \"Q1\" plan\nfinal")
        let csv = CSVExport.csv(sessions: [tricky], projects: projects, tags: tags)
        #expect(csv.contains("\"Board, \"\"Q1\"\" plan\nfinal\""))
        #expect(csv.hasSuffix("\r\n"))
    }

    @Test("unassigned time says so rather than being blank")
    func unassigned() {
        let csv = CSVExport.csv(sessions: [session(project: nil)], projects: [], tags: [])
        #expect(csv.contains("Unassigned"))
    }
}

@Suite("Splitting a session")
struct SplitSessionTests {
    let hour = 3600.0

    func original() -> Session {
        Session(
            id: "orig", appBundleID: "com.figma.Desktop", appName: "Figma",
            startTime: base, endTime: base.addingTimeInterval(8 * 3600),
            durationSeconds: 6 * 3600      // 8h at the desk, 6h of it active
        )
    }

    @Test("active time is shared in proportion to wall time")
    func proportionalSplit() {
        let result = SplitSession.split(
            original(), at: [base.addingTimeInterval(3 * hour)],
            into: [SplitSession.Part(projectId: "a"), SplitSession.Part(projectId: "b")]
        )
        guard case .success(let parts) = result else { Issue.record("expected a split"); return }

        // 3h and 5h of an 8h window, so 3/8 and 5/8 of the 6h active.
        #expect(parts[0].durationSeconds == 8100)
        #expect(parts[1].durationSeconds == 13500)
    }

    @Test("total active time is conserved exactly, whatever the rounding")
    func conservesTotal() {
        var awkward = original()
        awkward.durationSeconds = 6001
        let result = SplitSession.split(
            awkward,
            at: [base.addingTimeInterval(1234), base.addingTimeInterval(5678)],
            into: [
                SplitSession.Part(projectId: "a"),
                SplitSession.Part(projectId: "b"),
                SplitSession.Part(projectId: "c"),
            ]
        )
        guard case .success(let parts) = result else { Issue.record("expected a split"); return }
        #expect(parts.reduce(0) { $0 + $1.durationSeconds } == 6001,
                "reorganising time must never change how much there is")
    }

    @Test("parts get new ids and are marked as the manual decisions they are")
    func partsAreManual() {
        let result = SplitSession.split(
            original(), at: [base.addingTimeInterval(3 * hour)],
            into: [SplitSession.Part(projectId: "a"), SplitSession.Part()]
        )
        guard case .success(let parts) = result else { Issue.record("expected a split"); return }

        #expect(parts[0].id != "orig" && parts[1].id != "orig")
        #expect(parts[0].id != parts[1].id)
        #expect(parts[0].assignmentSource == .manualDashboard)
        #expect(parts[0].assignmentConfidence == Confidence.manual)
        #expect(parts[0].reviewed, "a part you assigned is reviewed by definition")
        #expect(!parts[1].reviewed, "a part left unassigned still needs a decision")
    }

    @Test("the original's identity and context are carried into every part")
    func preservesContext() {
        var source = original()
        source.appName = "Figma"
        source.windowTitle = "KPI Screens"
        let result = SplitSession.split(
            source, at: [base.addingTimeInterval(hour)],
            into: [SplitSession.Part(), SplitSession.Part()]
        )
        guard case .success(let parts) = result else { Issue.record("expected a split"); return }
        #expect(parts.allSatisfy { $0.appBundleID == "com.figma.Desktop" })
        #expect(parts.allSatisfy { $0.windowTitle == "KPI Screens" })
    }

    @Test("nonsensical splits are refused with a reason")
    func validation() {
        let one = [SplitSession.Part()]
        #expect(SplitSession.split(original(), at: [], into: one) == .failure(.tooFewParts))

        let two = [SplitSession.Part(), SplitSession.Part()]
        #expect(SplitSession.split(original(), at: [], into: two) == .failure(.boundaryCountMismatch))

        // Before the session started.
        #expect(SplitSession.split(
            original(), at: [base.addingTimeInterval(-hour)], into: two
        ) == .failure(.boundaryOutsideSession))

        // After it ended.
        #expect(SplitSession.split(
            original(), at: [base.addingTimeInterval(99 * hour)], into: two
        ) == .failure(.boundaryOutsideSession))

        let three = [SplitSession.Part(), SplitSession.Part(), SplitSession.Part()]
        #expect(SplitSession.split(
            original(),
            at: [base.addingTimeInterval(5 * hour), base.addingTimeInterval(2 * hour)],
            into: three
        ) == .failure(.boundariesOutOfOrder))
    }
}
