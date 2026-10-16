import XCTest
@testable import HeadsetGestureApp

final class MenuBarStateTests: XCTestCase {
    func testMissingPermissionWinsOverEverything() {
        XCTAssertEqual(
            MenuBarState.resolve(enabled: true, isConnected: true, accessibilityGranted: false, inputMonitoringGranted: true),
            .permissionMissing
        )
        XCTAssertEqual(
            MenuBarState.resolve(enabled: false, isConnected: false, accessibilityGranted: true, inputMonitoringGranted: false),
            .permissionMissing
        )
    }

    func testPausedWhenInterceptionIsOff() {
        XCTAssertEqual(
            MenuBarState.resolve(enabled: false, isConnected: true, accessibilityGranted: true, inputMonitoringGranted: true),
            .paused
        )
    }

    func testConnectedAndWaiting() {
        XCTAssertEqual(
            MenuBarState.resolve(enabled: true, isConnected: true, accessibilityGranted: true, inputMonitoringGranted: true),
            .connected
        )
        XCTAssertEqual(
            MenuBarState.resolve(enabled: true, isConnected: false, accessibilityGranted: true, inputMonitoringGranted: true),
            .waiting
        )
    }

    func testEveryStateHasATemplateImage() {
        for state in [MenuBarState.connected, .waiting, .paused, .permissionMissing] {
            let image = MenuBarIcon.image(for: state)
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        }
    }
}
