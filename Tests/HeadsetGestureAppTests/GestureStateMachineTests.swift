import XCTest
@testable import HeadsetGestureApp

final class GestureStateMachineTests: XCTestCase {
    func testSingleTapIsRecognizedAfterDoubleTapInterval() {
        var machine = GestureStateMachine(doubleTapInterval: 0.30, longPressDuration: 0.60)
        XCTAssertEqual(machine.buttonDown(at: 0.0), [])
        XCTAssertEqual(machine.buttonUp(at: 0.1), [])
        XCTAssertEqual(machine.tapSequenceThresholdReached(at: 0.39), [])
        XCTAssertEqual(machine.tapSequenceThresholdReached(at: 0.40), [.singleTap])
        XCTAssertEqual(machine.tapSequenceThresholdReached(at: 0.50), [])
    }

    func testDoubleTapIsRecognized() {
        var machine = GestureStateMachine(doubleTapInterval: 0.30, longPressDuration: 0.60)
        _ = machine.buttonDown(at: 0.0)
        XCTAssertEqual(machine.buttonUp(at: 0.05), [])
        _ = machine.buttonDown(at: 0.20)
        XCTAssertEqual(machine.buttonUp(at: 0.25), [])
        XCTAssertEqual(machine.tapSequenceThresholdReached(at: 0.54), [])
        XCTAssertEqual(machine.tapSequenceThresholdReached(at: 0.56), [.doubleTap])
    }

    func testTripleTapIsRecognizedOnThirdRelease() {
        var machine = GestureStateMachine(doubleTapInterval: 0.30, longPressDuration: 0.60)
        _ = machine.buttonDown(at: 0.0)
        XCTAssertEqual(machine.buttonUp(at: 0.05), [])
        _ = machine.buttonDown(at: 0.15)
        XCTAssertEqual(machine.buttonUp(at: 0.20), [])
        _ = machine.buttonDown(at: 0.30)
        XCTAssertEqual(machine.buttonUp(at: 0.35), [.tripleTap])
        XCTAssertEqual(machine.tapSequenceThresholdReached(at: 0.70), [])
    }

    func testTapOnlySingleTapDoesNotRequireRelease() {
        var machine = GestureStateMachine(doubleTapInterval: 0.30, longPressDuration: 0.60)

        XCTAssertEqual(machine.registerTap(at: 0.0), [])
        XCTAssertFalse(machine.isDown)
        XCTAssertEqual(machine.tapSequenceThresholdReached(at: 0.31), [.singleTap])
    }

    func testTapOnlyTripleTapUsesPressPulsesWithoutReleases() {
        var machine = GestureStateMachine(doubleTapInterval: 0.30, longPressDuration: 0.60)

        XCTAssertEqual(machine.registerTap(at: 0.0), [])
        XCTAssertEqual(machine.registerTap(at: 0.15), [])
        XCTAssertEqual(machine.registerTap(at: 0.30), [.tripleTap])
        XCTAssertFalse(machine.hasPendingTapSequence)
        XCTAssertFalse(machine.isDown)
    }

    func testExpiredThirdTapResolvesDoubleTapAndStartsNewSequence() {
        var machine = GestureStateMachine(doubleTapInterval: 0.30, longPressDuration: 0.60)
        _ = machine.buttonDown(at: 0.0)
        _ = machine.buttonUp(at: 0.05)
        _ = machine.buttonDown(at: 0.15)
        _ = machine.buttonUp(at: 0.20)

        XCTAssertEqual(machine.buttonDown(at: 0.51), [.doubleTap])
        XCTAssertEqual(machine.buttonUp(at: 0.56), [])
        XCTAssertEqual(machine.tapSequenceThresholdReached(at: 0.87), [.singleTap])
    }

    func testLongPressCancelsPendingTapSequence() {
        var machine = GestureStateMachine(doubleTapInterval: 0.30, longPressDuration: 0.60)
        _ = machine.buttonDown(at: 0.0)
        _ = machine.buttonUp(at: 0.05)
        _ = machine.buttonDown(at: 0.15)

        XCTAssertEqual(machine.buttonUp(at: 0.80), [.longPress])
        XCTAssertEqual(machine.tapSequenceThresholdReached(at: 1.20), [])
    }

    func testExpiredTapDoesNotBecomeDoubleTap() {
        var machine = GestureStateMachine(doubleTapInterval: 0.30, longPressDuration: 0.60)
        _ = machine.buttonDown(at: 0.0)
        _ = machine.buttonUp(at: 0.05)
        XCTAssertEqual(machine.buttonDown(at: 0.40), [.singleTap])
        XCTAssertEqual(machine.buttonUp(at: 0.45), [])
        XCTAssertEqual(machine.tapSequenceThresholdReached(at: 0.75), [.singleTap])
    }

    func testLongPressIsRecognizedOnlyOnRelease() {
        var machine = GestureStateMachine(doubleTapInterval: 0.30, longPressDuration: 0.60)
        _ = machine.buttonDown(at: 0.0)
        XCTAssertTrue(machine.isDown)
        XCTAssertEqual(machine.buttonUp(at: 0.90), [.longPress])
        XCTAssertEqual(machine.tapSequenceThresholdReached(at: 1.0), [])
    }

    func testLongPressCanBeRecognizedOnRelease() {
        var machine = GestureStateMachine(doubleTapInterval: 0.30, longPressDuration: 0.60)
        _ = machine.buttonDown(at: 0.0)
        XCTAssertEqual(machine.buttonUp(at: 0.61), [.longPress])
    }

    func testLongPressCanBeRecognizedImmediatelyAtThreshold() {
        var machine = GestureStateMachine(doubleTapInterval: 0.30, longPressDuration: 0.60)
        _ = machine.buttonDown(at: 0.0)

        XCTAssertEqual(machine.longPressThresholdReached(at: 0.59), [])
        XCTAssertEqual(machine.longPressThresholdReached(at: 0.60), [.longPress])
        XCTAssertEqual(machine.longPressThresholdReached(at: 0.80), [])
        XCTAssertEqual(machine.buttonUp(at: 0.90), [])
    }

    func testReleaseBeforeThresholdWinsOverDelayedLongPressCheck() {
        var machine = GestureStateMachine(doubleTapInterval: 0.30, longPressDuration: 0.60)
        _ = machine.buttonDown(at: 0.0)

        XCTAssertEqual(machine.buttonUp(at: 0.10), [])
        XCTAssertEqual(machine.tapSequenceThresholdReached(at: 0.40), [.singleTap])
    }

    func testStuckPressRecoveryPreservesTheNextTap() {
        var machine = GestureStateMachine(doubleTapInterval: 0.30, longPressDuration: 0.60)
        _ = machine.buttonDown(at: 0.0)

        XCTAssertFalse(machine.recoverStuckPress(at: 0.59))
        XCTAssertTrue(machine.recoverStuckPress(at: 1.50))
        XCTAssertFalse(machine.isDown)

        XCTAssertEqual(machine.buttonDown(at: 1.50), [])
        XCTAssertEqual(machine.buttonUp(at: 1.62), [])
        XCTAssertEqual(machine.tapSequenceThresholdReached(at: 1.93), [.singleTap])
    }

    func testTimedOutStuckPressRecoversNextReleaseOnlyTap() {
        var machine = GestureStateMachine(doubleTapInterval: 0.30, longPressDuration: 0.60)
        _ = machine.buttonDown(at: 0.0)

        XCTAssertTrue(
            machine.recoverStuckPress(
                at: 1.60,
                acceptingNextReleaseAsTap: true
            )
        )
        XCTAssertTrue(machine.isAwaitingReleaseOnlyTap)

        XCTAssertEqual(machine.buttonUp(at: 1.80), [])
        XCTAssertFalse(machine.isAwaitingReleaseOnlyTap)
        XCTAssertEqual(machine.tapSequenceThresholdReached(at: 2.11), [.singleTap])
    }

    func testRealDownSupersedesReleaseOnlyRecovery() {
        var machine = GestureStateMachine(doubleTapInterval: 0.30, longPressDuration: 0.60)
        _ = machine.buttonDown(at: 0.0)
        XCTAssertTrue(
            machine.recoverStuckPress(
                at: 1.60,
                acceptingNextReleaseAsTap: true
            )
        )

        XCTAssertEqual(machine.buttonDown(at: 1.80), [])
        XCTAssertFalse(machine.isAwaitingReleaseOnlyTap)
        XCTAssertEqual(machine.buttonUp(at: 1.90), [])
        XCTAssertEqual(machine.tapSequenceThresholdReached(at: 2.21), [.singleTap])
    }

    func testDiagnosticAttributesShortInputLongPressToAppDelay() {
        let diagnostic = GestureTimingDiagnostic(
            inputHoldDuration: 0.08,
            callbackHoldDuration: 0.65,
            longPressThreshold: 0.60,
            longPressWasEmitted: true
        )

        XCTAssertEqual(diagnostic.verdict, .appProcessingDelay)
        XCTAssertEqual(diagnostic.releaseProcessingDelay, 0.57, accuracy: 0.001)
    }

    func testDiagnosticAttributesLongRawSignalToInput() {
        let diagnostic = GestureTimingDiagnostic(
            inputHoldDuration: 0.68,
            callbackHoldDuration: 0.69,
            longPressThreshold: 0.60,
            longPressWasEmitted: true
        )

        XCTAssertEqual(diagnostic.verdict, .inputSignalHeld)
    }

    func testDiagnosticKeepsNormalTapNormal() {
        let diagnostic = GestureTimingDiagnostic(
            inputHoldDuration: 0.09,
            callbackHoldDuration: 0.10,
            longPressThreshold: 0.60,
            longPressWasEmitted: false
        )

        XCTAssertEqual(diagnostic.verdict, .normal)
    }
}
