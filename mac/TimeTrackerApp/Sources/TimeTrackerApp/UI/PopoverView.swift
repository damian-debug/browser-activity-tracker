import SwiftUI
import TimeTrackerCore

struct PopoverView: View {
    @Bindable var model: AppModel
    var openDashboard: () -> Void = {}
    @State private var newProjectName = ""
    @State private var showingNewProject = false
    @State private var newFeatureName = ""
    @State private var showingNewFeature = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            currentActivity
            if !model.accessibilityTrusted || !model.deniedBrowsers.isEmpty {
                Divider()
                permissions
            }
            Divider()
            favourites
            Divider()
            todaySummary
            Divider()
            footer
        }
        .frame(width: 320)
    }

    // ── Header ───────────────────────────────────────────────────────────

    private var header: some View {
        HStack {
            Text("Activity Tracker").font(.headline)
            Spacer()
            Button {
                Task { await model.togglePause() }
            } label: {
                Image(systemName: model.isManuallyPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.borderless)
            .help(model.isManuallyPaused ? "Resume tracking" : "Pause tracking")
        }
        .padding(12)
    }

    // ── What's being tracked right now ───────────────────────────────────

    private var currentActivity: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.isManuallyPaused {
                Label("Tracking paused", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            } else if model.status.isTracking {
                HStack(alignment: .firstTextBaseline) {
                    Text(DurationFormatter.clock(model.status.elapsedSeconds))
                        .font(.system(.title2, design: .rounded).monospacedDigit())
                    if model.status.isPaused {
                        Text(pauseLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(model.status.displayTitle ?? model.status.appName ?? "")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.status.projectId == nil ? Color.secondary : Color.accentColor)
                        .frame(width: 7, height: 7)

                    // The project is a menu, so correcting a wrong guess is one
                    // click from where the guess is shown — which is also where
                    // the model learns the most.
                    Menu {
                        Button("Unassigned") { Task { await model.assignCurrentSession(to: nil) } }
                        Divider()
                        ForEach(model.topLevelProjects) { project in
                            Button(project.name) {
                                Task { await model.assignCurrentSession(to: project) }
                            }
                        }
                    } label: {
                        Text(model.status.projectName ?? "Unassigned")
                            .font(.caption)
                            .foregroundStyle(model.status.projectId == nil ? .secondary : .primary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    // The feature within that project. Only shown once there is
                    // a project to hang it on, so it never adds noise for
                    // unassigned time.
                    if model.status.projectId != nil {
                        Text("›").font(.caption2).foregroundStyle(.tertiary)
                        featureMenu
                    }

                    if let source = model.status.assignmentSource, source == .suggested {
                        Text("suggested")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    if model.activeOverride != nil {
                        Button("Stop timer") { Task { await model.stopTimer() } }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }

                if showingNewFeature, let projectId = model.status.projectId {
                    HStack {
                        TextField("Feature name", text: $newFeatureName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addFeature(to: projectId) }
                        Button("Add") { addFeature(to: projectId) }
                            .disabled(newFeatureName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                // An automatic assignment must always be able to justify itself.
                if let explanation = model.suggestionExplanation {
                    Text(explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label("Nothing being tracked", systemImage: "moon.zzz")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Picking a feature is deliberately persistent: it stays set until you
    /// change it, because you know which feature you are on and the Mac does not.
    private var featureMenu: some View {
        Menu {
            Button("No feature") { Task { await model.setCurrentFeature(nil) } }
            if !model.featuresOfCurrentProject.isEmpty {
                Divider()
                ForEach(model.featuresOfCurrentProject) { feature in
                    Button(feature.name) { Task { await model.setCurrentFeature(feature) } }
                }
            }
            Divider()
            Button("New feature…") { showingNewFeature = true }
        } label: {
            Text(model.status.featureName ?? "Add feature")
                .font(.caption)
                .foregroundStyle(model.status.featureId == nil ? .secondary : .primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var pauseLabel: String {
        let reasons = model.status.pauseReasons
        if reasons.contains(.screenLocked) { return "locked" }
        if reasons.contains(.displayAsleep) { return "asleep" }
        if reasons.contains(.idle) { return "idle" }
        return "paused"
    }

    // ── Permissions ──────────────────────────────────────────────────────
    //
    // Shown only when something is actually missing, and always phrased as what
    // it unlocks rather than what the app wants. Everything keeps working
    // without these; the attribution is just coarser.

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.accessibilityTrusted {
                permissionRow(
                    title: "Track time per document",
                    detail: "Let Activity Tracker read the title and file of the window you're in, so time lands on the right project instead of just the right app.",
                    action: "Grant Access"
                ) {
                    model.requestAccessibility()
                    model.openAccessibilitySettings()
                }
            }

            ForEach(model.deniedBrowsers, id: \.self) { bundleID in
                permissionRow(
                    title: "Track websites in \(model.appName(forBundleID: bundleID))",
                    detail: "Automation is turned off for this browser, so its tabs are tracked as one lump instead of per site.",
                    action: "Open Settings"
                ) {
                    model.openAutomationSettings()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func permissionRow(
        title: String, detail: String, action: String, perform: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "lock.open").foregroundStyle(.secondary)
                Text(title).font(.caption.weight(.medium))
            }
            Text(detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(action, action: perform)
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    // ── Favourites ───────────────────────────────────────────────────────

    private var favourites: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("FAVOURITES").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingNewProject.toggle()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New project")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if showingNewProject {
                HStack {
                    TextField("Project name", text: $newProjectName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addProject() }
                    Button("Add") { addProject() }
                        .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }

            if model.favourites.isEmpty {
                Text("Star a project to pin it here for one-click tracking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
                ForEach(model.favourites) { project in
                    favouriteRow(project)
                }
                .padding(.bottom, 4)
            }
        }
    }

    private func favouriteRow(_ project: Project) -> some View {
        let isRunning = model.activeOverride?.projectId == project.id
        return Button {
            Task {
                if isRunning { await model.stopTimer() }
                else { await model.startTimer(for: project) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isRunning ? "stop.circle.fill" : "play.circle")
                    .foregroundStyle(isRunning ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name).lineLimit(1)
                    if let client = project.clientName, !client.isEmpty {
                        Text(client).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(DurationFormatter.short(secondsToday(project.id)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func secondsToday(_ projectId: String) -> Int {
        model.todayStats.projectTotals.first { $0.projectId == projectId }?.totalSeconds ?? 0
    }

    private func addFeature(to projectId: String) {
        let name = newFeatureName
        newFeatureName = ""
        showingNewFeature = false
        Task { await model.createFeature(named: name, in: projectId) }
    }

    private func addProject() {
        let name = newProjectName
        newProjectName = ""
        showingNewProject = false
        Task { await model.createProject(named: name) }
    }

    // ── Today ────────────────────────────────────────────────────────────

    private var todaySummary: some View {
        HStack {
            summaryItem("Today", model.todayStats.totalActiveSeconds, .primary)
            Spacer()
            summaryItem("Billable", model.todayStats.billableSeconds, .primary)
            Spacer()
            summaryItem(
                "Unassigned", model.todayStats.unassignedSeconds,
                model.todayStats.unassignedSeconds > 0 ? .orange : .primary
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func summaryItem(_ label: String, _ seconds: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DurationFormatter.short(seconds))
                .font(.callout.monospacedDigit())
                .foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // ── Footer ───────────────────────────────────────────────────────────

    private var footer: some View {
        VStack(spacing: 6) {
            HStack {
                Button("Dashboard…", action: openDashboard)
                    .buttonStyle(.borderless)
                    .font(.caption)
                Spacer()
                Toggle("Start at login", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { value in Task { await model.setLaunchAtLogin(value) } }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
            }
            HStack {
                if let error = model.lastError {
                    Text(error).font(.caption2).foregroundStyle(.red).lineLimit(1)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
