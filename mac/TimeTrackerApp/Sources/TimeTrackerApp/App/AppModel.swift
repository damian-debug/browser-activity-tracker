import AppKit
import Observation
import TimeTrackerCore

/// Wires the sensors to the coordinator and exposes state for the UI.
///
/// Everything the UI reads lives here as `@Observable` state, refreshed on a
/// timer, so the SwiftUI popover has no knowledge of actors or the database.
@MainActor
@Observable
final class AppModel {
    let store: TrackerStore
    private let coordinator: ActivityCoordinator

    private let sampler = ActivitySampler()
    private let idle: IdleMonitor
    private let power = PowerMonitor()
    private var tickTimer: Timer?

    // ── Observable state ─────────────────────────────────────────────────
    private(set) var status: TrackingStatus = .idle
    private(set) var todayStats: DashboardStats = .empty
    private(set) var favourites: [Project] = []
    private(set) var allProjects: [Project] = []
    private(set) var activeOverride: ActiveProjectOverride?
    private(set) var lastError: String?

    /// What the app can currently see. Drives the permission prompts in the UI
    /// and explains why attribution may be coarser than expected.
    private(set) var accessibilityTrusted = false
    private(set) var deniedBrowsers: [String] = []
    private(set) var unsupportedBrowsers: [String] = []

    var settings: AppSettings {
        didSet {
            try? store.saveSettings(settings)
            idle.thresholdSeconds = TimeInterval(settings.idleThresholdSeconds)
            Task { await coordinator.updateSettings(settings) }
        }
    }

    /// True when tracking is suspended by the user rather than by idleness.
    private(set) var isManuallyPaused = false

    init(store: TrackerStore) {
        self.store = store
        let settings = store.settings()
        self.settings = settings
        self.coordinator = ActivityCoordinator(dependencies: store, settings: settings)
        self.idle = IdleMonitor(thresholdSeconds: TimeInterval(settings.idleThresholdSeconds))
    }

    func start() {
        // Pick up anything left in flight by a crash, force-quit or restart.
        // The coordinator decides whether the gap since is plausible work.
        if let orphan = store.inFlightSession() {
            Task {
                await coordinator.restore(orphan)
                try? store.saveInFlightSession(nil)
                await refresh()
            }
        }

        sampler.onChange = { [weak self] snapshot in
            guard let self, !self.isManuallyPaused else { return }
            Task { await self.coordinator.observe(snapshot) }
        }
        idle.onChange = { [weak self] isIdle in
            guard let self else { return }
            Task {
                if isIdle {
                    await self.coordinator.pause(.idle)
                } else {
                    await self.coordinator.resume(.idle)
                }
                await self.refresh()
            }
        }
        power.onScreenLocked = { [weak self] locked in
            guard let self else { return }
            Task {
                if locked { await self.coordinator.pause(.screenLocked) }
                else { await self.coordinator.resume(.screenLocked) }
            }
        }
        power.onDisplayAsleep = { [weak self] asleep in
            guard let self else { return }
            Task {
                if asleep { await self.coordinator.pause(.displayAsleep) }
                else { await self.coordinator.resume(.displayAsleep) }
            }
        }
        power.onWake = { [weak self] in
            // Timers do not fire while asleep, so reconcile against the wall
            // clock rather than trusting elapsed ticks.
            guard let self else { return }
            Task { await self.coordinator.heartbeat() }
        }

        sampler.start()
        idle.start()
        power.start()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer

        Task { await refresh() }
    }

    private var secondsSinceHeartbeat = 0

    private func tick() async {
        // Checkpoint about every 30s, matching the extension's heartbeat: it
        // bounds how much is lost to a hard crash, and is the hook where a
        // slept machine gets noticed.
        secondsSinceHeartbeat += 1
        if secondsSinceHeartbeat >= 30 {
            secondsSinceHeartbeat = 0
            await coordinator.heartbeat()
            // Checkpoint to disk too, so an unclean exit costs one interval
            // rather than the entire session.
            try? store.saveInFlightSession(await coordinator.activeSession)
        }
        await refresh()
    }

    func refresh() async {
        status = await coordinator.status(now: Date())
        activeOverride = store.override()
        accessibilityTrusted = sampler.isAccessibilityTrusted
        deniedBrowsers = sampler.browserAccess
            .filter { $0.value == .denied }.keys.sorted()
        unsupportedBrowsers = sampler.browserAccess
            .filter { $0.value == .unsupported }.keys.sorted()
        do {
            allProjects = try store.projects()
            favourites = try store.favouriteProjects()
            let helpers = DateHelpers.current
            let today = helpers.todayDateString()
            if let from = helpers.startOfDay(today), let to = helpers.endOfDay(today) {
                let sessions = try store.sessions(from: from, to: to)
                todayStats = StatsBuilder.build(
                    sessions: sessions,
                    projects: allProjects,
                    tags: try store.tags(),
                    threshold: settings.reviewConfidenceThreshold
                )
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Close out cleanly on quit so the session in progress is banked.
    func shutdown() async {
        await coordinator.shutdown()
        try? store.saveInFlightSession(nil)
    }

    // ── Actions ──────────────────────────────────────────────────────────

    /// Start a manual timer on a project. Time is attributed here regardless of
    /// which app is frontmost, until stopped.
    func startTimer(for project: Project, countingWhileAway: Bool = false) async {
        let override = ActiveProjectOverride(
            projectId: project.id,
            billable: project.defaultBillable,
            scope: .global,
            expiry: .manual,
            countsWhileAway: countingWhileAway,
            startedAt: Date(),
            expiresAt: nil
        )
        try? store.saveOverride(override)
        await coordinator.restartCurrentSession(ignoringIdle: countingWhileAway)
        await refresh()
    }

    /// Drop the manual timer and go back to automatic attribution.
    func stopTimer() async {
        try? store.saveOverride(nil)
        await coordinator.restartCurrentSession(ignoringIdle: false)
        await refresh()
    }

    func togglePause() async {
        isManuallyPaused.toggle()
        if isManuallyPaused {
            await coordinator.endSession(at: Date())
        } else if let snapshot = sampler.currentSnapshot() {
            await coordinator.observe(snapshot)
        }
        await refresh()
    }

    func toggleFavourite(_ project: Project) async {
        var updated = project
        updated.isFavourite.toggle()
        updated.updatedAt = Date()
        try? store.save(updated)
        await refresh()
    }

    func createProject(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? store.save(Project(name: trimmed, isFavourite: true))
        await refresh()
    }

    // ── Permissions ──────────────────────────────────────────────────────

    /// Ask for Accessibility. macOS only shows a signpost to System Settings —
    /// there is no programmatic grant and no completion callback, so the answer
    /// shows up as `accessibilityTrusted` flipping on a later refresh.
    func requestAccessibility() {
        AccessibilityReader.requestAccess()
    }

    func openAccessibilitySettings() {
        AccessibilityReader.openSystemSettings()
    }

    func openAutomationSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        )!
        NSWorkspace.shared.open(url)
    }

    /// Human-readable name for a bundle id, for permission messages.
    func appName(forBundleID bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    /// Menu bar label: the elapsed clock plus a hint of what it is being
    /// counted against, kept short so it doesn't crowd the menu bar.
    var statusItemTitle: String {
        guard status.isTracking else { return "--" }
        let clock = DurationFormatter.clock(status.elapsedSeconds)
        if status.isPaused { return "|| \(clock)" }
        return clock
    }
}
