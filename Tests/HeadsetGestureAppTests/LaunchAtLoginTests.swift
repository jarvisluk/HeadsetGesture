import ServiceManagement
import XCTest
@testable import HeadsetGestureApp

final class LaunchAtLoginTests: XCTestCase {
    func testStateMapping() {
        XCTAssertEqual(LaunchAtLogin.state(for: .notRegistered), .off)
        XCTAssertEqual(LaunchAtLogin.state(for: .notFound), .off)
        XCTAssertEqual(LaunchAtLogin.state(for: .enabled), .on)
        XCTAssertEqual(LaunchAtLogin.state(for: .requiresApproval), .needsApproval)
    }

    func testRegisteredIncludesPendingApproval() {
        XCTAssertFalse(LaunchAtLoginState.off.isRegistered)
        XCTAssertTrue(LaunchAtLoginState.on.isRegistered)
        XCTAssertTrue(LaunchAtLoginState.needsApproval.isRegistered)
    }
}
