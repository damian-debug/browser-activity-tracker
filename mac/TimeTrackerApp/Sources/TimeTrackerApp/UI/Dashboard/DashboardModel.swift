import AppKit
import Observation
import TimeTrackerCore

@MainActor
@Observable
final class DashboardModel {
    enum Range: String, CaseIterable, Identifiable {
        case today = "Today"
        case yesterday = "Yesterday"
        case week = "Last 7 days"
        case month = "Last 30 days"
        var id: String { rawValue }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case projects = "Projects"
        case review = "Review Needed"
        case sessions = "Sessions"
        case apps = "Apps & Sites"
        var id: String { rawValue }
    }

    private let store: TrackerStore
    private let helpers = DateHelpers.current

    var range: Range = .today { didSet { reload() } }
    var tab: Tab = .projects

    private(set) var stats: DashboardStats = .empty
    private(set) var sessions: [Session] = []
    private(set) var projects: [Project] = []
    private(set) var tags: [Tag] = []
    private(set) var settings: AppSettings = .default
    private(set) var status: String?

    init(store: TrackerStore) {
        self.store = store
        reload()
    }

    var reviewSessions: [Session] {
        sessions.filter {
            StatsBuilder.needsReview($0, threshold: settings.reviewConfidenceThreshold)
        }
    }

    private var bounds: (from: Date, to: Date)? {
        let today = helpers.todayDateString()
        switch range {
        case .today:
            guard let from = helpers.startOfDay(today), let to = helpers.endOfDay(today) else { return nil }
            return (from, to)
        case .yesterday:
            let yesterday = helpers.daysAgoDateString(1)
            guard let from = helpers.startOfDay(yesterday), let to = helpers.endOfDay(yesterday) else { return nil }
            return (from, to)
        case .week:
            guard let from = helpers.startOfDay(helpers.daysAgoDateString(6)),
                  let to = helpers.endOfDay(today) else { return nil }
            return (from, to)
        case .month:
            guard let from = helpers.startOfDay(helpers.daysAgoDateString(29)),
                  let to = helpers.endOfDay(today) else { return nil }
            return (from, to)
        }
    }

    func reload() {
        settings = store.settings()
        guard let bounds else { return }
        do {
            projects = try store.projects()
            tags = try store.tags()
            sessions = try store.sessions(from: bounds.from, to: bounds.to)
            stats = StatsBuilder.build(
                sessions: sessions, projects: projects, tags: tags,
                threshold: settings.reviewConfidenceThreshold
            )
            status = nil
        } catch {
            status = error.localizedDescription
        }
    }

    var topLevelProjects: [Project] { projects.topLevel }

    func features(of projectId: String?) -> [Project] {
        guard let projectId else { return [] }
        return projects.features(of: projectId)
    }

    func projectName(_ id: String?) -> String {
        guard let id else { return "Unassigned" }
        return projects.first { $0.id == id }?.name ?? "Unknown project"
    }

    func featureName(_ id: String?) -> String {
        guard let id else { return "—" }
        return projects.first { $0.id == id }?.name ?? "Unknown feature"
    }

    func tagNames(_ ids: [String]) -> String {
        ids.compactMap { id in tags.first { $0.id == id }?.name }.joined(separator: ", ")
    }

    // ── Editing ──────────────────────────────────────────────────────────

    /// Set just the feature, leaving the project alone.
    func assign(_ session: Session, toFeature feature: Project?) {
        var updated = session
        updated.featureId = feature?.id
        updated.featureName = feature?.name
        updated.reviewed = true
        do {
            try store.updateSession(updated)
            try teachModel(previous: nil, updated: updated)
            reload()
        } catch {
            status = error.localizedDescription
        }
    }

    func assign(_ session: Session, to project: Project?) {
        var updated = session
        updated.projectId = project?.id
        updated.projectName = project?.name
        // A feature belongs to one project, so moving the project drops a
        // feature that no longer applies rather than leaving it dangling.
        if project?.id != session.projectId {
            updated.featureId = nil
            updated.featureName = nil
        }
        updated.assignmentSource = project == nil ? .unassigned : .manualDashboard
        updated.assignmentConfidence = project == nil ? 0 : Confidence.manual
        updated.matchedRuleId = nil
        // Deciding is itself the review — but clearing a project is not a
        // decision about what the time *was*, so it goes back in the queue.
        updated.reviewed = project != nil
        if let project { updated.billable = project.defaultBillable }

        do {
            try store.updateSession(updated)
            try teachModel(previous: session, updated: updated)
            reload()
        } catch {
            status = error.localizedDescription
        }
    }

    func assignAll(_ toAssign: [Session], to project: Project) {
        for session in toAssign { assign(session, to: project) }
    }

    func markReviewed(_ session: Session) {
        var updated = session
        updated.reviewed = true
        do {
            try store.updateSession(updated)
            // Confirming a suggestion is a real endorsement, so it counts as
            // evidence even though the app's own guess would not.
            try teachModel(previous: nil, updated: updated)
            reload()
        } catch {
            status = error.localizedDescription
        }
    }

    func delete(_ session: Session) {
        do {
            try store.deleteSession(id: session.id)
            reload()
        } catch {
            status = error.localizedDescription
        }
    }

    /// Feed a human decision back into the learned model.
    private func teachModel(previous: Session?, updated: Session) throws {
        guard settings.learningEnabled, let projectId = updated.projectId else { return }
        let index = LearnedIndex.default

        var observations = index.observations(for: updated, projectId: projectId)
        if let featureId = updated.featureId {
            observations += index.observations(for: updated, projectId: featureId)
        }

        // If this overturned an earlier assignment, penalise the old answer as
        // well as rewarding the new one.
        if let previous, let wrong = previous.projectId, wrong != projectId {
            observations += index.corrections(for: previous, wrongProjectId: wrong)
        }
        try store.recordObservations(observations)
    }

    // ── Rules ────────────────────────────────────────────────────────────

    func ruleSuggestions(for session: Session) -> [RuleSuggestion] {
        RuleSuggester.suggestions(for: session)
    }

    /// Create a rule from a session and apply it to matching past work.
    /// Returns how many earlier sessions it claimed.
    @discardableResult
    func createRule(
        _ suggestion: RuleSuggestion, from session: Session, project: Project
    ) -> Int {
        do {
            let rule = RuleSuggester.rule(
                from: suggestion, projectId: project.id, projectName: project.name
            )
            try store.save(rule)

            // Reach back over everything, not just the visible range: the point
            // of a rule is that it settles this question once.
            let all = try store.allSessions()
            let claimed = RuleBackfill.sessionsToUpdate(matching: rule, in: all)
            for old in claimed {
                try store.updateSession(
                    RuleBackfill.applied(rule, to: old, projectName: project.name)
                )
            }
            reload()
            status = claimed.isEmpty
                ? "Rule created."
                : "Rule created, and applied to \(claimed.count) earlier session\(claimed.count == 1 ? "" : "s")."
            return claimed.count
        } catch {
            status = error.localizedDescription
            return 0
        }
    }

    // ── Export ───────────────────────────────────────────────────────────

    func exportCSV() {
        let csv = CSVExport.csv(sessions: sessions, projects: projects, tags: tags)
        save(text: csv, suggestedName: "activity-\(helpers.todayDateString()).csv")
    }

    func exportBackup() {
        do {
            let data = try Backup.encode(try store.backupContents())
            save(data: data, suggestedName: "activity-tracker-backup-\(helpers.todayDateString()).json")
        } catch {
            status = error.localizedDescription
        }
    }

    func importBackup(mode: ImportMode) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = mode == .replace
            ? "Choose a backup to replace everything on this Mac."
            : "Choose a backup to merge into what is already here."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            switch Backup.decode(data) {
            case .failure(let error):
                status = error.description
            case .success(let contents):
                let plan = Backup.plan(contents, existing: try store.backupContents(), mode: mode)
                try store.apply(plan)
                reload()
                status = "Imported \(plan.sessions.count) session\(plan.sessions.count == 1 ? "" : "s")"
                    + (plan.skipped > 0 ? ", skipped \(plan.skipped) already newer here." : ".")
            }
        } catch {
            status = error.localizedDescription
        }
    }

    private func save(text: String, suggestedName: String) {
        save(data: Data(text.utf8), suggestedName: suggestedName)
    }

    private func save(data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            status = "Saved to \(url.lastPathComponent)."
        } catch {
            status = error.localizedDescription
        }
    }
}
