import XCTest
@testable import HeadsetGestureApp

final class GestureFeedbackSoundTests: XCTestCase {
    func testDefaultSoundsDifferPerGesture() {
        let sounds = GestureSoundSet()
        let chosen = RecognizedGesture.allCases.map { sounds.sound(for: $0) }
        XCTAssertEqual(Set(chosen).count, RecognizedGesture.allCases.count)
    }

    func testEveryChoiceIsAnInstalledSystemSound() {
        for sound in FeedbackSound.allCases {
            let path = "/System/Library/Sounds/\(sound.rawValue).aiff"
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), path)
        }
    }

    @MainActor
    func testChosenSoundSavesAndReloads() {
        let suiteName = "GestureFeedbackSoundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.gestureSounds, GestureSoundSet())
        store.gestureSounds.setSound(.glass, for: .doubleTap)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.gestureSounds.sound(for: .doubleTap), .glass)
        XCTAssertEqual(reloaded.gestureSounds.sound(for: .singleTap), .morse)
    }
}
