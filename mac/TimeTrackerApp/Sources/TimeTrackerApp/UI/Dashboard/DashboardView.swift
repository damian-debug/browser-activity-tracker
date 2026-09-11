import SwiftUI
import TimeTrackerCore

struct DashboardView: View {
    @Bindable var model: DashboardModel
    @State private var ruleSheetSession: Session?
    @State private var editingRule: DashboardModel.RuleDraft?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            summary
            Divider()
            Picker("", selection: $model.tab) {
                ForEach(DashboardModel.Tab.allCases) { tab in
                    if tab == .rules, !model.rules.isEmpty {
                        Text("\(tab.rawValue) (\(model.rules.count))").tag(tab)
                    } else if tab == .review, !model.reviewSessions.isEmpty {
                        Text("\(tab.rawValue) (\(model.reviewSessions.count))").tag(tab)
                    } else {
                        Text(tab.rawValue).tag(tab)
                    }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()
            content
            if let status = model.status {
                Divider()
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .sheet(item: $ruleSheetSession) { session in
            // Seeded from the session's narrowest suggestion, and from whatever
            // it is already assigned to.
            RuleEditor(
                model: model,
                session: session,
                draft: DashboardModel.RuleDraft(
                    model.ruleSuggestions(for: session).first
                        ?? RuleSuggestion(label: "", type: .appBundleEquals, value: session.appBundleID),
                    projectId: session.projectId,
                    featureId: session.featureId
                )
            )
        }
        .sheet(item: $editingRule) { draft in
            RuleEditor(model: model, session: nil, draft: draft)
        }
    }

    private var header: some View {
        HStack {
            Picker("", selection: $model.range) {
                ForEach(DashboardModel.Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 380)

            Spacer()

            Button("Export CSV") { model.exportCSV() }
            Menu("Backup") {
                Button("Save backup…") { model.exportBackup() }
                Divider()
                Button("Restore (merge)…") { model.importBackup(mode: .merge) }
                Button("Restore (replace everything)…") { model.importBackup(mode: .replace) }
            }
            .fixedSize()
        }
        .padding(12)
    }

    private var summary: some View {
        HStack(spacing: 24) {
            card("Tracked", DurationFormatter.long(model.stats.totalActiveSeconds), .primary)
            card("Billable", DurationFormatter.long(model.stats.billableSeconds), .primary)
            card("Unassigned", DurationFormatter.long(model.stats.unassignedSeconds),
                 model.stats.unassignedSeconds > 0 ? .orange : .primary)
            card("Needs review", "\(model.stats.needsReviewCount)",
                 model.stats.needsReviewCount > 0 ? .orange : .primary)
            if model.stats.awaySeconds > 0 {
                card("Away", DurationFormatter.long(model.stats.awaySeconds), .secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func card(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.tab {
        case .projects: ProjectTotalsTable(model: model)
        case .review: ReviewQueueView(model: model, ruleSheetSession: $ruleSheetSession)
        case .sessions: SessionTable(model: model, ruleSheetSession: $ruleSheetSession)
        case .apps: AppsAndSitesTable(model: model)
        case .rules: RulesTable(model: model, editing: $editingRule)
        }
    }
}

// ── Projects ─────────────────────────────────────────────────────────────

private struct ProjectTotalsTable: View {
    let model: DashboardModel

    var body: some View {
        VSplitView {
            Table(model.stats.projectTotals) {
                TableColumn("Project") { Text($0.projectName) }
                TableColumn("Client") { Text($0.clientName ?? "") }
                TableColumn("Tracked") { Text(DurationFormatter.long($0.totalSeconds)) }
                TableColumn("Billable") { Text(DurationFormatter.long($0.billableSeconds)) }
                TableColumn("Sessions") { Text("\($0.sessionCount)") }
            }

            if !model.stats.featureTotals.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Features")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.top, 8)
                    Table(model.stats.featureTotals) {
                        TableColumn("Feature") { Text($0.featureName) }
                        TableColumn("Project") { Text($0.projectName).foregroundStyle(.secondary) }
                        TableColumn("Tracked") { Text(DurationFormatter.long($0.totalSeconds)) }
                        TableColumn("Billable") { Text(DurationFormatter.long($0.billableSeconds)) }
                        TableColumn("Sessions") { Text("\($0.sessionCount)") }
                    }
                }
            }
        }
    }
}

// ── Apps & sites ─────────────────────────────────────────────────────────

private struct AppsAndSitesTable: View {
    let model: DashboardModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("Apps")
                Table(model.stats.apps) {
                    TableColumn("App") { Text($0.appName) }
                    TableColumn("Tracked") { Text(DurationFormatter.long($0.totalSeconds)) }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("Sites & files")
                Table(model.stats.domains) {
                    TableColumn("Site") { Text($0.domain) }
                    TableColumn("Tracked") { Text(DurationFormatter.long($0.totalSeconds)) }
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.top, 8)
    }
}

// ── Sessions ─────────────────────────────────────────────────────────────

private struct SessionTable: View {
    let model: DashboardModel
    @Binding var ruleSheetSession: Session?

    var body: some View {
        Table(model.sessions) {
            TableColumn("Started") { session in
                Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            TableColumn("Duration") { Text(DurationFormatter.short($0.durationSeconds)) }
            TableColumn("What") { session in
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.windowTitle ?? session.url ?? session.appName).lineLimit(1)
                    Text(session.appName).font(.caption2).foregroundStyle(.secondary)
                }
            }
            TableColumn("Project") { session in
                ProjectMenu(model: model, session: session)
            }
            TableColumn("Feature") { session in
                FeatureMenu(model: model, session: session)
            }
            TableColumn("Source") { session in
                Text(sourceLabel(session)).font(.caption).foregroundStyle(.secondary)
            }
            TableColumn("") { session in
                Button("Rule…") { ruleSheetSession = session }.buttonStyle(.link)
            }
        }
    }

    private func sourceLabel(_ session: Session) -> String {
        switch session.assignmentSource {
        case .autoRule: return "rule · \(session.assignmentConfidence)"
        case .suggested: return "learned · \(session.assignmentConfidence)"
        case .manualPopup, .manualDashboard: return "manual"
        case .activeProjectOverride: return "timer"
        case .unassigned: return "—"
        }
    }
}

// ── Review queue ─────────────────────────────────────────────────────────

private struct ReviewQueueView: View {
    let model: DashboardModel
    @Binding var ruleSheetSession: Session?
    @State private var selection = Set<Session.ID>()

    var body: some View {
        VStack(spacing: 0) {
            if model.reviewSessions.isEmpty {
                ContentUnavailableView(
                    "Nothing to review",
                    systemImage: "checkmark.circle",
                    description: Text("Every session in this range has a project you've confirmed.")
                )
            } else {
                if !selection.isEmpty {
                    batchBar
                    Divider()
                }
                Table(model.reviewSessions, selection: $selection) {
                    TableColumn("Started") { session in
                        Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Duration") { Text(DurationFormatter.short($0.durationSeconds)) }
                    TableColumn("What") { session in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.windowTitle ?? session.url ?? session.appName).lineLimit(1)
                            Text(session.appName).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    TableColumn("Suggested") { session in
                        if session.assignmentSource == .suggested, let id = session.projectId {
                            Text("\(model.projectName(id)) · \(session.assignmentConfidence)")
                                .font(.caption)
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                    TableColumn("Project") { session in
                        ProjectMenu(model: model, session: session)
                    }
                    TableColumn("") { session in
                        HStack(spacing: 8) {
                            Button("Rule…") { ruleSheetSession = session }.buttonStyle(.link)
                            if session.projectId != nil {
                                Button("Confirm") { model.markReviewed(session) }.buttonStyle(.link)
                            }
                        }
                    }
                }
            }
        }
    }

    private var batchBar: some View {
        HStack {
            Text("\(selection.count) selected").font(.caption)
            Spacer()
            Menu("Assign all to…") {
                ForEach(model.topLevelProjects) { project in
                    Button(project.name) {
                        let chosen = model.reviewSessions.filter { selection.contains($0.id) }
                        model.assignAll(chosen, to: project)
                        selection.removeAll()
                    }
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

// ── Shared ───────────────────────────────────────────────────────────────

private struct ProjectMenu: View {
    let model: DashboardModel
    let session: Session

    var body: some View {
        Menu {
            Button("Unassigned") { model.assign(session, to: nil) }
            Divider()
            ForEach(model.topLevelProjects) { project in
                Button(project.name) { model.assign(session, to: project) }
            }
        } label: {
            Text(model.projectName(session.projectId))
                .foregroundStyle(session.projectId == nil ? .secondary : .primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct FeatureMenu: View {
    let model: DashboardModel
    let session: Session

    var body: some View {
        let features = model.features(of: session.projectId)
        if features.isEmpty {
            Text("—").foregroundStyle(.tertiary)
        } else {
            Menu {
                Button("None") { model.assign(session, toFeature: nil) }
                Divider()
                ForEach(features) { feature in
                    Button(feature.name) { model.assign(session, toFeature: feature) }
                }
            } label: {
                Text(session.featureId == nil ? "—" : model.featureName(session.featureId))
                    .foregroundStyle(session.featureId == nil ? .secondary : .primary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

/// Creating or changing a rule.
///
/// Suggestions seed the form rather than being the whole of it: the app can see
/// what you did, but only you know how far it should generalise.
struct RuleEditor: View {
    let model: DashboardModel
    /// The session this was opened from, if any — its suggestions seed the form.
    var session: Session?
    @State var draft: DashboardModel.RuleDraft
    @Environment(\.dismiss) private var dismiss

    @State private var applyToPast = true
    @State private var addingFeature = false
    @State private var newFeatureName = ""

    /// Stands in for "New feature…" in the Feature picker. Never stored: the
    /// picker's binding turns it into showing the name field instead. Real
    /// feature ids are UUIDs, so this cannot collide with one.
    private static let newFeatureTag = "new-feature-placeholder"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.ruleId == nil ? "New rule" : "Edit rule").font(.headline)

            if let session {
                suggestions(for: session)
                Divider()
            }

            form
            impact
            Divider()

            HStack {
                Toggle("Also apply to matching past sessions", isOn: $applyToPast)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button("Cancel") { dismiss() }
                Button(draft.ruleId == nil ? "Create rule" : "Save") {
                    model.save(draft, applyToPast: applyToPast)
                    dismiss()
                }
                .keyboardShortcut(addingFeature ? nil : .defaultAction)
                .disabled(!draft.isValid || addingFeature)
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    // ── Suggestions ──────────────────────────────────────────────────────

    private func suggestions(for session: Session) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Start from what you were doing")
                .font(.caption).foregroundStyle(.secondary)
            Text("Narrowest first — a broad rule quietly swallows unrelated work.")
                .font(.caption2).foregroundStyle(.tertiary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.ruleSuggestions(for: session)) { suggestion in
                        let selected = draft.resolvedConditions == suggestion.conditions
                        HStack(spacing: 8) {
                            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(selected ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(suggestion.label).font(.caption)
                                Text(suggestion.conditions.summary)
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text("\(suggestion.confidence)")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            draft.conditions = suggestion.conditions
                                .map(DashboardModel.RuleDraft.Condition.init)
                        }
                    }
                }
            }
            .frame(maxHeight: 140)
        }
    }

    // ── The rule itself ──────────────────────────────────────────────────

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Project", selection: $draft.projectId) {
                    Text("Choose…").tag(String?.none)
                    ForEach(model.topLevelProjects) { Text($0.name).tag(String?.some($0.id)) }
                }
                .onChange(of: draft.projectId) { _, _ in
                    // A feature belongs to one project, so it cannot survive
                    // the project changing underneath it.
                    draft.featureId = nil
                    draft.pendingFeature = nil
                    addingFeature = false
                }

                Picker("Feature", selection: featureSelection) {
                    Text("None").tag(String?.none)
                    ForEach(model.features(for: draft)) {
                        Text($0.name).tag(String?.some($0.id))
                    }
                    Divider()
                    Text("New feature…").tag(String?.some(Self.newFeatureTag))
                }
                .disabled(draft.projectId == nil)
            }

            if addingFeature, let projectId = draft.projectId {
                HStack {
                    TextField("New feature in \(model.projectName(projectId))", text: $newFeatureName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        model.chooseFeature(named: newFeatureName, in: &draft)
                        addingFeature = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newFeatureName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { addingFeature = false }
                }
            } else if let pending = draft.pendingFeature, pending.id == draft.featureId {
                Text("“\(pending.name)” is new — it is created when you save this rule.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            // Every condition must hold. This is what makes shared tools
            // workable: Slack is not a project, but Slack and a channel is.
            VStack(alignment: .leading, spacing: 6) {
                ForEach($draft.conditions) { $condition in
                    ConditionRow(
                        model: model,
                        condition: $condition,
                        isFirst: draft.conditions.first?.id == condition.id,
                        canRemove: draft.conditions.count > 1
                    ) {
                        draft.conditions.removeAll { $0.id == condition.id }
                    }
                }

                Button {
                    draft.conditions.append(DashboardModel.RuleDraft.Condition())
                } label: {
                    Label("Add condition", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            TextField("Name (optional)", text: $draft.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// Choosing "New feature…" opens the name field rather than selecting
    /// anything, so the picker keeps showing the previous choice meanwhile.
    private var featureSelection: Binding<String?> {
        Binding(
            get: { draft.featureId },
            set: { value in
                if value == Self.newFeatureTag {
                    newFeatureName = ""
                    addingFeature = true
                } else {
                    draft.featureId = value
                }
            }
        )
    }

    /// What this rule would actually do to the history already recorded.
    @ViewBuilder
    private var impact: some View {
        if let impact = model.impact(of: draft) {
            HStack(spacing: 6) {
                Image(systemName: impact.claims > 0 ? "checkmark.circle" : "circle.dashed")
                    .foregroundStyle(impact.claims > 0 ? Color.accentColor : .secondary)
                Text(impactText(impact))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Choose a project and a value to see what this would match.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func impactText(_ impact: (claims: Int, alreadyDecided: Int)) -> String {
        var text = impact.claims == 1
            ? "Would claim 1 unassigned session"
            : "Would claim \(impact.claims) unassigned sessions"
        if impact.alreadyDecided > 0 {
            // Named rather than hidden: a rule matching a lot of settled work
            // is usually a sign it is broader than intended.
            text += ", and also matches \(impact.alreadyDecided) you have already decided (left untouched)"
        }
        return text + "."
    }
}

/// One "and" clause of a rule.
private struct ConditionRow: View {
    let model: DashboardModel
    @Binding var condition: DashboardModel.RuleDraft.Condition
    let isFirst: Bool
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(isFirst ? "Match on" : "and")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)

                Picker("", selection: $condition.type) {
                    ForEach(ProjectRuleType.allCases, id: \.self) { type in
                        Text(label(for: type)).tag(type)
                    }
                }
                .labelsHidden()
                .fixedSize()

                TextField(placeholder, text: $condition.value)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                if !pickableValues.isEmpty {
                    Menu {
                        ForEach(pickableValues, id: \.value) { option in
                            Button(option.label) { condition.value = option.value }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Choose from what you have tracked")
                }

                Button(role: .destructive, action: remove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(!canRemove)
                .opacity(canRemove ? 1 : 0.3)
            }

            if condition.type == .queryParamEquals {
                TextField("Parameter name", text: $condition.queryParamName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.leading, 64)
            }

            if let problem = condition.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 64)
            }
        }
    }

    /// Values worth offering outright, where the set is small and knowable.
    /// Everything else stays free text — there is no useful list of every
    /// window title you have ever had.
    private var pickableValues: [(label: String, value: String)] {
        switch condition.type {
        case .appBundleEquals:
            return model.knownApps.map { (label: "\($0.name)  —  \($0.bundleID)", value: $0.bundleID) }
        case .domainEquals:
            return model.knownSites.map { (label: $0, value: $0) }
        default:
            return []
        }
    }

    private var placeholder: String {
        switch condition.type {
        case .appBundleEquals: return "com.figma.Desktop"
        case .domainEquals: return "figma.com"
        case .documentPathContains: return "/Projects/acme/"
        case .titleContains: return "acme-internal"
        case .queryParamEquals: return "the value to match"
        case .regex: return "a regular expression"
        default: return "the text to match"
        }
    }

    private func label(for type: ProjectRuleType) -> String {
        switch type {
        case .domainEquals: return "Site is"
        case .urlContains: return "URL contains"
        case .urlStartsWith: return "URL starts with"
        case .pathContains: return "URL path contains"
        case .queryParamEquals: return "URL parameter equals"
        case .titleContains: return "Window title contains"
        case .regex: return "URL matches regex"
        case .appBundleEquals: return "App is"
        case .documentPathContains: return "File path contains"
        }
    }
}

// ── Rules ────────────────────────────────────────────────────────────────

private struct RulesTable: View {
    let model: DashboardModel
    @Binding var editing: DashboardModel.RuleDraft?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Rules assign work automatically from now on.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("New rule…") { editing = model.newRuleDraft() }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.rules.isEmpty {
            ContentUnavailableView {
                Label("No rules yet", systemImage: "text.badge.checkmark")
            } description: {
                Text("Write one here, or create one from a session in Review Needed.")
            } actions: {
                Button("New rule…") { editing = model.newRuleDraft() }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.rulesGroupedByProject(), id: \.project) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.project)
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(group.rules) { rule in
                                row(rule)
                                Divider()
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func row(_ rule: ProjectRule) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { model.setRule(rule, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.name).fontWeight(.medium)
                    if let featureId = rule.featureId {
                        Text("› \(model.featureName(featureId))")
                            .font(.caption)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
                Text(rule.summary)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            .opacity(rule.enabled ? 1 : 0.5)

            Spacer()

            Text("\(rule.confidence)")
                .font(.caption2).foregroundStyle(.tertiary)
                .help("Confidence this rule assigns")
            Button("Edit") { editing = DashboardModel.RuleDraft(rule) }.buttonStyle(.link)
            Button("Apply to past") { model.applyToPast(rule) }.buttonStyle(.link)
            Button("Delete", role: .destructive) { model.delete(rule) }.buttonStyle(.link)
        }
    }
}
