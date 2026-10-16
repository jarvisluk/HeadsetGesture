import AppKit
import XCTest
@testable import HeadsetGestureApp

final class KeyActionTests: XCTestCase {
    func testExtendedFunctionKeyCodes() {
        XCTAssertEqual(KeyChoice.f13.keyCode, 105)
        XCTAssertEqual(KeyChoice.f16.keyCode, 106)
        XCTAssertEqual(KeyChoice.f17.keyCode, 64)
        XCTAssertEqual(KeyChoice.f20.keyCode, 90)
    }

    func testLeftAndRightModifierKeyCodes() {
        XCTAssertEqual(KeyChoice.leftControl.keyCode, 59)
        XCTAssertEqual(KeyChoice.rightControl.keyCode, 62)
        XCTAssertEqual(KeyChoice.leftOption.keyCode, 58)
        XCTAssertEqual(KeyChoice.rightOption.keyCode, 61)
        XCTAssertEqual(KeyChoice.leftCommand.keyCode, 55)
        XCTAssertEqual(KeyChoice.rightCommand.keyCode, 54)

        XCTAssertEqual(KeyChoice.leftControl.modifierFlag, .maskControl)
        XCTAssertEqual(KeyChoice.rightControl.modifierFlag, .maskControl)
        XCTAssertEqual(KeyChoice.leftOption.modifierFlag, .maskAlternate)
        XCTAssertEqual(KeyChoice.rightOption.modifierFlag, .maskAlternate)
        XCTAssertEqual(KeyChoice.leftCommand.modifierFlag, .maskCommand)
        XCTAssertEqual(KeyChoice.rightCommand.modifierFlag, .maskCommand)
    }

    func testModifierKeyTitlesAreSideSpecific() {
        XCTAssertEqual(KeyChoice.leftControl.title, "Left Control")
        XCTAssertEqual(KeyChoice.rightOption.title, "Right Option")
        XCTAssertEqual(KeyChoice.rightCommand.title, "Right Command")
    }

    func testSynthesizedKeyboardEventsAreMarkedForLocalSuppression() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))
        let cgEvent = try XCTUnwrap(
            CGEvent(keyboardEventSource: source, virtualKey: KeyChoice.f13.keyCode, keyDown: true)
        )
        let originalEvent = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
        XCTAssertFalse(SynthesizedEventGuard.shouldSuppressInsideApp(originalEvent))

        SynthesizedEventGuard.mark(cgEvent)
        let markedEvent = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
        XCTAssertTrue(SynthesizedEventGuard.shouldSuppressInsideApp(markedEvent))
    }

    func testMediaKeyCodes() {
        XCTAssertEqual(MediaKeyChoice.volumeUp.nxKeyCode, 0)
        XCTAssertEqual(MediaKeyChoice.mute.nxKeyCode, 7)
        XCTAssertEqual(MediaKeyChoice.playPause.nxKeyCode, 16)
        XCTAssertEqual(MediaKeyChoice.next.nxKeyCode, 17)
        XCTAssertEqual(KeyAction.defaultSingleTap.summary, "Play/Pause")
    }

    func testKeyboardActionSummaryIncludesModifiers() {
        var action = KeyAction.defaultDoubleTap
        action.control = true
        action.command = true
        action.key = .f20
        XCTAssertEqual(action.summary, "⌃⌘F20")
    }

    func testShortcutAndCommandSummaries() {
        var shortcut = KeyAction.defaultDoubleTap
        shortcut.kind = .shortcut
        shortcut.shortcutName = "Log Time"
        XCTAssertEqual(shortcut.summary, "Shortcut: Log Time")

        var command = KeyAction.defaultLongPress
        command.kind = .command
        command.shellCommand = "open -a Notes"
        XCTAssertEqual(command.summary, "open -a Notes")
    }
}
