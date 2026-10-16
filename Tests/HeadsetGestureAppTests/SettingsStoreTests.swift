import Foundation
import XCTest
@testable import HeadsetGestureApp

final class SettingsStoreTests: XCTestCase {
    @MainActor
    func testNestedActionChangesSaveAndReloadImmediately() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.singleTapAction.kind = .keyboard
        store.singleTapAction.key = .rightCommand
        store.singleTapAction.option = true
        store.tripleTapAction = .defaultTripleTap
        store.tripleTapAction.enabled = true
        store.tripleTapAction.key = .f16

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.singleTapAction.kind, .keyboard)
        XCTAssertEqual(reloaded.singleTapAction.key, .rightCommand)
        XCTAssertTrue(reloaded.singleTapAction.option)
        XCTAssertTrue(reloaded.tripleTapAction.enabled)
        XCTAssertEqual(reloaded.tripleTapAction.key, .f16)
        XCTAssertNotNil(store.lastSavedAt)
        XCTAssertNil(store.saveErrorText)
    }

    @MainActor
    func testDetectionIntervalsSaveAndReloadImmediately() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.doubleTapInterval = 0.45
        store.longPressDuration = 0.85
        store.longPressRecognitionEnabled = true
        store.longPressTriggerMode = .immediately
        store.showLongPressDuration = false
        store.longPressDisplayPosition = .focusedInput

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.doubleTapInterval, 0.45)
        XCTAssertEqual(reloaded.longPressDuration, 0.85)
        XCTAssertTrue(reloaded.longPressRecognitionEnabled)
        XCTAssertEqual(reloaded.longPressTriggerMode, .immediately)
        XCTAssertFalse(reloaded.showLongPressDuration)
        XCTAssertEqual(reloaded.longPressDisplayPosition, .focusedInput)
        XCTAssertNotNil(store.lastSavedAt)
    }

    @MainActor
    func testTripleTapDefaultsToDisabled() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(SettingsStore(defaults: defaults).tripleTapAction.enabled)
    }

    @MainActor
    func testLongPressRecognitionDefaultsToDisabled() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(SettingsStore(defaults: defaults).longPressRecognitionEnabled)
    }

    @MainActor
    func testDockIconDefaultsToVisibleAndPersists() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.showDockIcon)

        store.showDockIcon = false
        XCTAssertFalse(SettingsStore(defaults: defaults).showDockIcon)
    }

    func testDockIconVisibilityMapsToActivationPolicy() {
        XCTAssertEqual(DockIconVisibility.activationPolicy(showDockIcon: true), .regular)
        XCTAssertEqual(DockIconVisibility.activationPolicy(showDockIcon: false), .accessory)
    }
}
