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
        case rules = "Rules"
        var id: String { rawValue }
    }

    /// An editable rule, whether it is being created or changed.
    ///
    /// Suggestions are a starting point rather than a fixed menu: the app can
    /// see what you did, but only you know how far it should generalise.
    struct RuleDraft: Equatable, Identifiable {
        /// One editable condition. Identified so SwiftUI can track rows as
        /// they are added and removed.
        struct Condition: Equatable, Identifiable {
            let id = UUID()
            var type: ProjectRuleType = .appBundleEquals
            var value: String = ""
            var queryParamName: String = ""

            var isValid: Bool {
                !value.trimmingCharacters(in: .whitespaces).isEmpty
                    && (type != .queryParamEquals
                        || !queryParamName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            var resolved: RuleCondition {
                RuleCondition(
                    type: type,
                    value: value.trimmingCharacters(in: .whitespaces),
                    queryParamName: type == .queryParamEquals
                        ? queryParamName.trimmingCharacters(in: .whitespaces)
                        : nil
                )
            }

            init() {}

            init(_ condition: RuleCondition) {
                type = condition.type
                value = condition.value
                queryParamName = condition.queryParamName ?? ""
            }
        }

        /// The rule being edited, or nil when creating a new one.
        var ruleId: String?
        /// Sheets are presented by item, so a new draft still needs an identity.
        public var id: String { ruleId ?? "new" }

        var name: String = ""
        /// All must hold. Slack is not a project; Slack and a channel name is.
        var conditions: [Condition] = [Condition()]
        var projectId: String?
        var featureId: String?
        var enabled: Bool = true

        var isValid: Bool {
            projectId != nil && !conditions.isEmpty && conditions.allSatisfy(\.isValid)
        }

        var resolvedConditions: [RuleCondition] { conditions.map(\.resolved) }

        // Conveniences for the single-condition case, which is most of them.
        // They read and write the FIRST condition only.
        var type: ProjectRuleType {
            get { conditions.first?.type ?? .appBundleEquals }
            set {
                if conditions.isEmpty { conditions = [Condition()] }
                conditions[0].type = newValue
            }
        }
        var value: String {
            get { conditions.first?.value ?? "" }
            set {
                if conditions.isEmpty { conditions = [Condition()] }
                conditions[0].value = newValue
            }
        }
        var queryParamName: String {
            get { conditions.first?.queryParamName ?? "" }
            set {
                if conditions.isEmpty { conditions = [Condition()] }
                conditions[0].queryParamName = newValue
            }
        }

        init() {}

        init(_ rule: ProjectRule) {
            ruleId = rule.id
            name = rule.name
            conditions = rule.conditions.map(Condition.init)
            projectId = rule.projectId
            featureId = rule.featureId
            enabled = rule.enabled
        }

        init(_ suggestion: RuleSuggestion, projectId: String?, featureId: String?) {
            conditions = suggestion.conditions.map(Condition.init)
            self.projectId = projectId
            self.featureId = featureId
        }
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
    private(set) var rules: [ProjectRule] = []
    private(set) var knownApps: [(bundleID: String, name: String)] = []
    private(set) var knownSites: [String] = []
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
            rules = try store.rules()
            knownApps = try store.knownApps()
            knownSites = try store.knownSites()
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

    // ── Rule management ──────────────────────────────────────────────────

    /// How many stored sessions a candidate rule would claim, and how many it
    /// would touch that are already settled.
    ///
    /// Shown while editing because the difference between a useful rule and one
    /// that swallows half your history is a single path segment, and there is
    /// no way to know which without looking.
    func impact(of draft: RuleDraft) -> (claims: Int, alreadyDecided: Int)? {
        guard draft.isValid, let candidate = rule(from: draft) else { return nil }
        guard let all = try? store.allSessions() else { return nil }

        let claims = RuleBackfill.sessionsToUpdate(matching: candidate, in: all).count
        let decided = all.filter { session in
            guard session.projectId != nil || session.reviewed else { return false }
            return RuleEngine.run(RuleBackfill.context(for: session), rules: [candidate]).projectId != nil
        }.count
        return (claims, decided)
    }

    private func rule(from draft: RuleDraft) -> ProjectRule? {
        guard let projectId = draft.projectId else { return nil }
        let projectName = self.projectName(projectId)
        let featureLabel = draft.featureId.map { " › " + featureName($0) } ?? ""
        let name = draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            ? "\(projectName)\(featureLabel)"
            : draft.name

        return ProjectRule(
            id: draft.ruleId ?? UUID().uuidString,
            projectId: projectId,
            featureId: draft.featureId,
            name: name,
            conditions: draft.resolvedConditions,
            enabled: draft.enabled,
            updatedAt: Date()
        )
    }

    /// Save a rule, and optionally apply it to work already recorded.
    @discardableResult
    func save(_ draft: RuleDraft, applyToPast: Bool) -> Int {
        guard let candidate = rule(from: draft) else { return 0 }
        do {
            try store.save(candidate)
            var claimed = 0
            if applyToPast {
                claimed = try backfill(candidate)
            }
            reload()
            status = claimed == 0
                ? "Rule saved."
                : "Rule saved, and applied to \(claimed) earlier session\(claimed == 1 ? "" : "s")."
            return claimed
        } catch {
            status = error.localizedDescription
            return 0
        }
    }

    private func backfill(_ rule: ProjectRule) throws -> Int {
        let all = try store.allSessions()
        let claimed = RuleBackfill.sessionsToUpdate(matching: rule, in: all)
        for old in claimed {
            try store.updateSession(RuleBackfill.applied(
                rule, to: old,
                projectName: projectName(rule.projectId),
                featureName: rule.featureId.map(featureName)
            ))
        }
        return claimed.count
    }

    func setRule(_ rule: ProjectRule, enabled: Bool) {
        var updated = rule
        updated.enabled = enabled
        updated.updatedAt = Date()
        do {
            try store.save(updated)
            reload()
            // Turning a rule off leaves the time it already assigned alone:
            // that was a decision, and undoing it silently would be worse.
            status = enabled ? "Rule enabled." : "Rule disabled. Time it already assigned is unchanged."
        } catch {
            status = error.localizedDescription
        }
    }

    func delete(_ rule: ProjectRule) {
        do {
            try store.deleteRule(id: rule.id)
            reload()
            status = "Rule deleted. Time it already assigned is unchanged."
        } catch {
            status = error.localizedDescription
        }
    }

    /// Apply an existing rule to work recorded before it existed.
    func applyToPast(_ rule: ProjectRule) {
        do {
            let claimed = try backfill(rule)
            reload()
            status = claimed == 0
                ? "Nothing left for that rule to claim."
                : "Applied to \(claimed) earlier session\(claimed == 1 ? "" : "s")."
        } catch {
            status = error.localizedDescription
        }
    }

    /// A blank rule, for writing one without a session to start from.
    func newRuleDraft() -> RuleDraft {
        var draft = RuleDraft()
        // The least surprising starting point when there is no context: an app
        // is something you can pick from a list rather than have to recall.
        draft.conditions = [RuleDraft.Condition()]
        draft.projectId = topLevelProjects.first?.id
        return draft
    }

    func rulesGroupedByProject() -> [(project: String, rules: [ProjectRule])] {
        Dictionary(grouping: rules) { $0.projectId }
            .map { (project: projectName($0.key), rules: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.project < $1.project }
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
