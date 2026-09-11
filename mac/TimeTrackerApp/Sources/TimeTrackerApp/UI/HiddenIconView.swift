import SwiftUI

/// The tracker in a window, for when its menu bar icon cannot be seen.
///
/// Shown when macOS has hidden the icon — usually because the menu bar is full
/// — or whenever the app is opened again from Spotlight or Applications. The
/// whole popover is embedded, so nothing is out of reach while the icon is.
struct HiddenIconView: View {
    @Bindable var model: AppModel
    /// True when the icon is known to be hidden; false when the window was
    /// simply asked for and the icon may well be visible.
    var iconHidden: Bool
    var openMenuBarSettings: () -> Void
    var openDashboard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if iconHidden {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Your menu bar is full", systemImage: "menubar.rectangle")
                        .font(.headline)
                    Text("Activity Tracker is running and tracking, but there is no room left in your menu bar, so macOS is hiding its icon.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("To make room, turn off an app or two under **Allow in the Menu Bar**. Until then, open Activity Tracker from Spotlight to bring this window back.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Menu Bar Settings…", action: openMenuBarSettings)
                        .controlSize(.small)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                Divider()
            }
            PopoverView(model: model, openDashboard: openDashboard)
        }
        .frame(width: 320)
    }
}
