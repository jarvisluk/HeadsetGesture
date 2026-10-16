import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var synthesizedKeyboardMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        synthesizedKeyboardMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { event in
            SynthesizedEventGuard.shouldSuppressInsideApp(event) ? nil : event
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let synthesizedKeyboardMonitor {
            NSEvent.removeMonitor(synthesizedKeyboardMonitor)
        }
        UserDefaults.standard.synchronize()
    }
}

@MainActor
final class AppModel: ObservableObject {
    let settings: SettingsStore
    let controller: HeadsetController
    private var dockIconSubscription: AnyCancellable?

    init() {
        SettingsStore.migrateLegacyDefaults()
        let settings = SettingsStore()
        let longPressDurationOverlay = LongPressDurationOverlayController(settings: settings)
        self.settings = settings
        controller = HeadsetController(
            settings: settings,
            longPressDurationOverlay: longPressDurationOverlay
        )
        if settings.enabled {
            controller.start()
        }
        dockIconSubscription = settings.$showDockIcon
            .removeDuplicates()
            .sink { showDockIcon in
                DockIconVisibility.apply(showDockIcon: showDockIcon)
            }
    }
}

@main
struct HeadsetGestureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        // A single-instance Window so "Open Dashboard…" focuses the existing
        // window instead of stacking a new copy on every click.
        Window("Headset Gesture", id: "main") {
            SettingsView(settings: model.settings, controller: model.controller)
        }
        .defaultSize(width: 620, height: 780)

        MenuBarExtra {
            MenuContentView(settings: model.settings, controller: model.controller)
        } label: {
            MenuBarLabel(settings: model.settings, controller: model.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar item: an 18 pt template image that follows the controller state.
/// A separate view so it observes the controller and settings directly.
private struct MenuBarLabel: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: HeadsetController

    var body: some View {
        let state = MenuBarState.resolve(
            enabled: settings.enabled,
            isConnected: controller.isConnected,
            accessibilityGranted: controller.accessibilityGranted,
            inputMonitoringGranted: controller.inputMonitoringGranted
        )
        Image(nsImage: MenuBarIcon.image(for: state))
            .accessibilityLabel("Headset Gesture – \(state.title)")
    }
}
