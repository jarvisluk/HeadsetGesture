import Foundation
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case off
    case on
    case needsApproval

    /// Registered with launchd, whether or not the user still has to approve it.
    var isRegistered: Bool {
        self == .on || self == .needsApproval
    }
}

enum LaunchAtLogin {
    static func state(for status: SMAppService.Status) -> LaunchAtLoginState {
        switch status {
        case .enabled:
            return .on
        case .requiresApproval:
            return .needsApproval
        case .notRegistered, .notFound:
            return .off
        @unknown default:
            return .off
        }
    }
}

/// Launch-at-login for the main app. `SMAppService` is the source of truth so a
/// change made in System Settings stays in sync; nothing is written to UserDefaults.
@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var state: LaunchAtLoginState
    @Published private(set) var errorText: String?

    var isOn: Bool { state.isRegistered }

    init(service: SMAppService = .mainApp) {
        self.service = service
        state = LaunchAtLogin.state(for: service.status)
    }

    func refresh() {
        state = LaunchAtLogin.state(for: service.status)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if !isOn {
                    try service.register()
                }
            } else if isOn {
                try service.unregister()
            }
            errorText = nil
        } catch {
            errorText = "Could not update login item"
        }
        refresh()
    }

    private let service: SMAppService
}
