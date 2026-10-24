import XCTest
@testable import HeadsetGestureApp

final class HeadsetButtonTests: XCTestCase {
    func testConsumerUsagesMapToButtons() {
        XCTAssertEqual(HeadsetButton(usagePage: 0x0c, usage: 0xcd), .playPause)
        XCTAssertEqual(HeadsetButton(usagePage: 0x0c, usage: 0xe9), .volumeUp)
        XCTAssertEqual(HeadsetButton(usagePage: 0x0c, usage: 0xea), .volumeDown)
        XCTAssertNil(HeadsetButton(usagePage: 0x0c, usage: 0xb5))
        XCTAssertNil(HeadsetButton(usagePage: 0x0b, usage: 0xe9))
    }

    func testVolumeDefaultsKeepVolumeOnSingleTapOnly() {
        let up = ButtonGestureMapping.defaultVolumeUp
        XCTAssertTrue(up.singleTap.enabled)
        XCTAssertEqual(up.singleTap.kind, .media)
        XCTAssertEqual(up.singleTap.mediaKey, .volumeUp)
        XCTAssertFalse(up.doubleTap.enabled)
        XCTAssertFalse(up.tripleTap.enabled)
        XCTAssertFalse(up.longPress.enabled)
        XCTAssertEqual(up.maxTapCount, 1)

        XCTAssertEqual(ButtonGestureMapping.defaultVolumeDown.singleTap.mediaKey, .volumeDown)
    }

    func testMaxTapCountFollowsLongestEnabledSequence() {
        var mapping = ButtonGestureMapping.defaultVolumeUp
        mapping.doubleTap.enabled = true
        XCTAssertEqual(mapping.maxTapCount, 2)
        mapping.tripleTap.enabled = true
        XCTAssertEqual(mapping.maxTapCount, 3)
        mapping.doubleTap.enabled = false
        XCTAssertEqual(mapping.maxTapCount, 3)
    }

    func testHeadsetNameMatchIsCaseInsensitive() {
        XCTAssertTrue(HeadsetDeviceFilter.isHeadsetName("Headset"))
        XCTAssertTrue(HeadsetDeviceFilter.isHeadsetName("HUAWEI USB-C HEADSET"))
        XCTAssertFalse(HeadsetDeviceFilter.isHeadsetName("2.4G Wireless Receiver"))
    }
}
