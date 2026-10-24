import Foundation

/// A physical headset button, identified by its HID Consumer usage.
enum HeadsetButton: String, CaseIterable, Identifiable {
    case playPause
    case volumeUp
    case volumeDown

    var id: String { rawValue }

    init?(usagePage: UInt32, usage: UInt32) {
        guard usagePage == 0x0c else { return nil }
        switch usage {
        case 0xcd: self = .playPause
        case 0xe9: self = .volumeUp
        case 0xea: self = .volumeDown
        default: return nil
        }
    }

    var usage: UInt32 {
        switch self {
        case .playPause: return 0xcd
        case .volumeUp: return 0xe9
        case .volumeDown: return 0xea
        }
    }

    var title: String {
        switch self {
        case .playPause: return "Play/Pause"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        }
    }

    var shortTitle: String {
        switch self {
        case .playPause: return "Play/Pause"
        case .volumeUp: return "Vol+"
        case .volumeDown: return "Vol−"
        }
    }

    var signalText: String {
        String(format: "Consumer %@ (0x%02X)", title, usage)
    }
}

/// The four gesture actions of one button.
struct ButtonGestureMapping: Codable, Equatable {
    var singleTap: KeyAction
    var doubleTap: KeyAction
    var tripleTap: KeyAction
    var longPress: KeyAction

    func action(for gesture: RecognizedGesture) -> KeyAction {
        switch gesture {
        case .singleTap: return singleTap
        case .doubleTap: return doubleTap
        case .tripleTap: return tripleTap
        case .longPress: return longPress
        }
    }

    mutating func setAction(_ action: KeyAction, for gesture: RecognizedGesture) {
        switch gesture {
        case .singleTap: singleTap = action
        case .doubleTap: doubleTap = action
        case .tripleTap: tripleTap = action
        case .longPress: longPress = action
        }
    }

    /// The longest tap sequence that has an action. Shorter sequences resolve
    /// as soon as this count is reached instead of waiting for more taps.
    var maxTapCount: Int {
        if tripleTap.enabled { return 3 }
        if doubleTap.enabled { return 2 }
        return 1
    }

    static let defaultVolumeUp = volumeDefault(.volumeUp)
    static let defaultVolumeDown = volumeDefault(.volumeDown)

    /// Single tap keeps the button's usual meaning; the other gestures start off
    /// so repeated presses are not read as double or triple taps.
    private static func volumeDefault(_ mediaKey: MediaKeyChoice) -> ButtonGestureMapping {
        var action = KeyAction.defaultSingleTap
        action.mediaKey = mediaKey
        var disabled = action
        disabled.enabled = false
        return ButtonGestureMapping(
            singleTap: action,
            doubleTap: disabled,
            tripleTap: disabled,
            longPress: disabled
        )
    }
}

/// Consumer keys a seized device can send besides the mapped buttons. Seizing
/// hides them from macOS, so they are re-posted as the matching system key.
enum ConsumerKeyPassthrough {
    /// The NX_KEYTYPE code for a Consumer usage, or nil when macOS has none.
    static func nxKeyCode(usagePage: UInt32, usage: UInt32) -> Int? {
        guard usagePage == 0x0c else { return nil }
        switch usage {
        case 0x6f: return 2 // Display Brightness Increment → NX_KEYTYPE_BRIGHTNESS_UP
        case 0x70: return 3 // Display Brightness Decrement → NX_KEYTYPE_BRIGHTNESS_DOWN
        case 0xb0, 0xb1: return 16 // Play, Pause → NX_KEYTYPE_PLAY
        case 0xb3: return 19 // Fast Forward → NX_KEYTYPE_FAST
        case 0xb4: return 20 // Rewind → NX_KEYTYPE_REWIND
        case 0xb5: return 17 // Scan Next Track → NX_KEYTYPE_NEXT
        case 0xb6: return 18 // Scan Previous Track → NX_KEYTYPE_PREVIOUS
        case 0xb8: return 14 // Eject → NX_KEYTYPE_EJECT
        case 0xe2: return 7 // Mute → NX_KEYTYPE_MUTE
        default: return nil
        }
    }
}
