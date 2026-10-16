import CoreGraphics
import XCTest
@testable import HeadsetGestureApp

final class LongPressDisplayPositionTests: XCTestCase {
    func testAllDisplayPositionsUseVisibleScreenFrame() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 1_000, height: 700)
        let windowSize = CGSize(width: 200, height: 80)
        let inset: CGFloat = 20

        XCTAssertEqual(
            LongPressDisplayPosition.topLeft.windowOrigin(
                windowSize: windowSize,
                visibleFrame: visibleFrame,
                inset: inset
            ),
            CGPoint(x: 120, y: 650)
        )
        XCTAssertEqual(
            LongPressDisplayPosition.top.windowOrigin(
                windowSize: windowSize,
                visibleFrame: visibleFrame,
                inset: inset
            ),
            CGPoint(x: 500, y: 650)
        )
        XCTAssertEqual(
            LongPressDisplayPosition.topRight.windowOrigin(
                windowSize: windowSize,
                visibleFrame: visibleFrame,
                inset: inset
            ),
            CGPoint(x: 880, y: 650)
        )
        XCTAssertEqual(
            LongPressDisplayPosition.center.windowOrigin(
                windowSize: windowSize,
                visibleFrame: visibleFrame,
                inset: inset
            ),
            CGPoint(x: 500, y: 360)
        )
        XCTAssertEqual(
            LongPressDisplayPosition.bottomLeft.windowOrigin(
                windowSize: windowSize,
                visibleFrame: visibleFrame,
                inset: inset
            ),
            CGPoint(x: 120, y: 70)
        )
        XCTAssertEqual(
            LongPressDisplayPosition.bottom.windowOrigin(
                windowSize: windowSize,
                visibleFrame: visibleFrame,
                inset: inset
            ),
            CGPoint(x: 500, y: 70)
        )
        XCTAssertEqual(
            LongPressDisplayPosition.bottomRight.windowOrigin(
                windowSize: windowSize,
                visibleFrame: visibleFrame,
                inset: inset
            ),
            CGPoint(x: 880, y: 70)
        )
        XCTAssertEqual(
            LongPressDisplayPosition.focusedInput.windowOrigin(
                windowSize: windowSize,
                visibleFrame: visibleFrame,
                inset: inset
            ),
            CGPoint(x: 500, y: 70)
        )
    }

    func testFocusedInputPlacementPrefersRightSide() {
        let origin = FocusedInputOverlayPlacement.windowOrigin(
            nextTo: CGRect(x: 200, y: 300, width: 300, height: 40),
            windowSize: CGSize(width: 176, height: 84),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 700)
        )

        XCTAssertEqual(origin, CGPoint(x: 512, y: 278))
    }

    func testFocusedInputPlacementUsesLeftSideWhenRightSideDoesNotFit() {
        let origin = FocusedInputOverlayPlacement.windowOrigin(
            nextTo: CGRect(x: 760, y: 20, width: 220, height: 40),
            windowSize: CGSize(width: 176, height: 84),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 700)
        )

        XCTAssertEqual(origin, CGPoint(x: 572, y: 12))
    }
}
