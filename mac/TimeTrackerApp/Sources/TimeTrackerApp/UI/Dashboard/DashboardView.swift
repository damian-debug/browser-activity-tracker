import SwiftUI
import TimeTrackerCore

struct DashboardView: View {
    @Bindable var model: DashboardModel
    @State private var ruleSheetSession: Session?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            summary
            Divider()
            Picker("", selection: $model.tab) {
                ForEach(DashboardModel.Tab.allCases) { tab in
                    if tab == .review, !model.reviewSessions.isEmpty {
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
            CreateRuleSheet(model: model, session: session)
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

/// Turning one decision into a standing rule.
private struct CreateRuleSheet: View {
    let model: DashboardModel
    let session: Session
    @Environment(\.dismiss) private var dismiss

    @State private var chosen: RuleSuggestion?
    @State private var project: Project?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Always track work like this").font(.headline)
            Text("Pick how far this should reach. The narrowest option is safest — a broad rule can quietly swallow unrelated work.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Project", selection: $project) {
                Text("Choose a project…").tag(Project?.none)
                ForEach(model.projects) { Text($0.name).tag(Project?.some($0)) }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.ruleSuggestions(for: session)) { suggestion in
                        HStack(spacing: 8) {
                            Image(systemName: chosen == suggestion ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(chosen == suggestion ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(suggestion.label)
                                Text(suggestion.value)
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text("\(suggestion.confidence)")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { chosen = suggestion }
                    }
                }
            }
            .frame(maxHeight: 220)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create rule") {
                    if let chosen, let project {
                        model.createRule(chosen, from: session, project: project)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen == nil || project == nil)
            }
        }
        .padding(16)
        .frame(width: 460)
        .onAppear {
            chosen = model.ruleSuggestions(for: session).first
            project = model.projects.first { $0.id == session.projectId }
        }
    }
}
