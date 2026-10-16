import AppKit

enum DockIconVisibility {
    static func activationPolicy(showDockIcon: Bool) -> NSApplication.ActivationPolicy {
        showDockIcon ? .regular : .accessory
    }

    /// Info.plist sets `LSUIElement`, so the app launches without a Dock icon and is
    /// promoted to `.regular` here only when the user wants one. This avoids the
    /// icon flashing in the Dock on launch when it is hidden.
    @MainActor
    static func apply(showDockIcon: Bool) {
        let policy = activationPolicy(showDockIcon: showDockIcon)
        guard NSApp.activationPolicy() != policy else { return }

        let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        NSApp.setActivationPolicy(policy)

        // Changing the policy deactivates the app, which pushes an open dashboard
        // behind other windows. Re-activate so it stays in front.
        guard hasVisibleWindow else { return }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
