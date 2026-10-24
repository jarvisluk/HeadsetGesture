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
        store.playGestureSound = true

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.doubleTapInterval, 0.45)
        XCTAssertEqual(reloaded.longPressDuration, 0.85)
        XCTAssertTrue(reloaded.longPressRecognitionEnabled)
        XCTAssertEqual(reloaded.longPressTriggerMode, .immediately)
        XCTAssertFalse(reloaded.showLongPressDuration)
        XCTAssertEqual(reloaded.longPressDisplayPosition, .focusedInput)
        XCTAssertTrue(reloaded.playGestureSound)
        XCTAssertNotNil(store.lastSavedAt)
    }

    @MainActor
    func testVolumeButtonMappingsSaveAndReloadIndependently() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.gestureMapping(for: .volumeUp), .defaultVolumeUp)
        XCTAssertEqual(store.gestureMapping(for: .volumeDown), .defaultVolumeDown)

        var doubleTap = KeyAction.defaultDoubleTap
        doubleTap.key = .f18
        store.setAction(doubleTap, for: .doubleTap, on: .volumeUp)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.gestureMapping(for: .volumeUp).doubleTap.key, .f18)
        XCTAssertEqual(reloaded.gestureMapping(for: .volumeDown), .defaultVolumeDown)
        XCTAssertEqual(reloaded.doubleTapAction, .defaultDoubleTap, "Play/Pause mappings must not change")
    }

    @MainActor
    func testPlayPauseMappingUsesOriginalActionKeys() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        var longPress = KeyAction.defaultLongPress
        longPress.key = .f19
        store.setAction(longPress, for: .longPress, on: .playPause)

        XCTAssertEqual(store.longPressAction.key, .f19)
        XCTAssertEqual(SettingsStore(defaults: defaults).gestureMapping(for: .playPause).longPress.key, .f19)
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

    @MainActor
    func testLegacyDefaultsMigrateOnceWithoutOverwriting() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let legacyName = "SettingsStoreTests.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let legacy = UserDefaults(suiteName: legacyName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            legacy.removePersistentDomain(forName: legacyName)
        }

        let legacyStore = SettingsStore(defaults: legacy)
        legacyStore.doubleTapInterval = 0.4
        legacyStore.singleTapAction.key = .rightOption
        legacyStore.singleTapAction.kind = .keyboard
        defaults.set(false, forKey: "showDockIcon")
        legacy.set(true, forKey: "showDockIcon")

        SettingsStore.migrateLegacyDefaults(into: defaults, from: legacy)
        let migrated = SettingsStore(defaults: defaults)
        XCTAssertEqual(migrated.doubleTapInterval, 0.4)
        XCTAssertEqual(migrated.singleTapAction.key, .rightOption)
        XCTAssertFalse(migrated.showDockIcon, "existing values must not be overwritten")

        // A second run must not re-import values the user has since changed.
        migrated.doubleTapInterval = 0.25
        SettingsStore.migrateLegacyDefaults(into: defaults, from: legacy)
        XCTAssertEqual(SettingsStore(defaults: defaults).doubleTapInterval, 0.25)
    }
}
