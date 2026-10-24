import AppKit
import CoreGraphics
import Foundation

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case keyboard
    case rawKeyCode
    case media
    case shortcut
    case command

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keyboard: return "Keyboard key or shortcut"
        case .rawKeyCode: return "Raw virtual key code (experimental)"
        case .media: return "Media key"
        case .shortcut: return "macOS Shortcut"
        case .command: return "Shell command"
        }
    }
}

enum KeyChoice: String, Codable, CaseIterable, Identifiable {
    case f13, f14, f15, f16, f17, f18, f19, f20
    case space, returnKey, escape, tab
    case leftControl, rightControl
    case leftOption, rightOption
    case leftCommand, rightCommand
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z

    var id: String { rawValue }

    var title: String {
        switch self {
        case .f13: return "F13"
        case .f14: return "F14"
        case .f15: return "F15"
        case .f16: return "F16"
        case .f17: return "F17"
        case .f18: return "F18"
        case .f19: return "F19"
        case .f20: return "F20"
        case .space: return "Space"
        case .returnKey: return "Return"
        case .escape: return "Escape"
        case .tab: return "Tab"
        case .leftControl: return "Left Control"
        case .rightControl: return "Right Control"
        case .leftOption: return "Left Option"
        case .rightOption: return "Right Option"
        case .leftCommand: return "Left Command"
        case .rightCommand: return "Right Command"
        default: return rawValue.uppercased()
        }
    }

    var keyCode: CGKeyCode {
        switch self {
        case .a: return 0
        case .s: return 1
        case .d: return 2
        case .f: return 3
        case .h: return 4
        case .g: return 5
        case .z: return 6
        case .x: return 7
        case .c: return 8
        case .v: return 9
        case .b: return 11
        case .q: return 12
        case .w: return 13
        case .e: return 14
        case .r: return 15
        case .y: return 16
        case .t: return 17
        case .o: return 31
        case .u: return 32
        case .i: return 34
        case .p: return 35
        case .returnKey: return 36
        case .l: return 37
        case .j: return 38
        case .k: return 40
        case .n: return 45
        case .m: return 46
        case .tab: return 48
        case .space: return 49
        case .escape: return 53
        case .leftCommand: return 55
        case .leftOption: return 58
        case .leftControl: return 59
        case .rightOption: return 61
        case .rightControl: return 62
        case .rightCommand: return 54
        case .f17: return 64
        case .f18: return 79
        case .f19: return 80
        case .f20: return 90
        case .f13: return 105
        case .f16: return 106
        case .f14: return 107
        case .f15: return 113
        }
    }

    var modifierFlag: CGEventFlags? {
        switch self {
        case .leftControl, .rightControl:
            return .maskControl
        case .leftOption, .rightOption:
            return .maskAlternate
        case .leftCommand, .rightCommand:
            return .maskCommand
        default:
            return nil
        }
    }
}

enum MediaKeyChoice: String, Codable, CaseIterable, Identifiable {
    case playPause
    case next
    case previous
    case volumeUp
    case volumeDown
    case mute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playPause: return "Play/Pause"
        case .next: return "Next Track"
        case .previous: return "Previous Track"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .mute: return "Mute"
        }
    }

    var nxKeyCode: Int {
        switch self {
        case .volumeUp: return 0
        case .volumeDown: return 1
        case .mute: return 7
        case .playPause: return 16
        case .next: return 17
        case .previous: return 18
        }
    }
}

struct KeyAction: Codable, Equatable {
    var enabled: Bool
    var kind: ActionKind
    var key: KeyChoice
    var rawKeyCode: UInt16
    var mediaKey: MediaKeyChoice
    var shortcutName: String
    var shellCommand: String
    var command: Bool
    var option: Bool
    var control: Bool
    var shift: Bool

    static let defaultSingleTap = KeyAction(
        enabled: true,
        kind: .media,
        key: .space,
        rawKeyCode: 110,
        mediaKey: .playPause,
        shortcutName: "",
        shellCommand: "",
        command: false,
        option: false,
        control: false,
        shift: false
    )

    static let defaultDoubleTap = KeyAction(
        enabled: true,
        kind: .keyboard,
        key: .f13,
        rawKeyCode: 110,
        mediaKey: .next,
        shortcutName: "",
        shellCommand: "",
        command: false,
        option: false,
        control: false,
        shift: false
    )

    static let defaultTripleTap = KeyAction(
        enabled: false,
        kind: .keyboard,
        key: .f15,
        rawKeyCode: 110,
        mediaKey: .next,
        shortcutName: "",
        shellCommand: "",
        command: false,
        option: false,
        control: false,
        shift: false
    )

    static let defaultLongPress = KeyAction(
        enabled: true,
        kind: .keyboard,
        key: .f14,
        rawKeyCode: 110,
        mediaKey: .previous,
        shortcutName: "",
        shellCommand: "",
        command: false,
        option: false,
        control: false,
        shift: false
    )

    var summary: String {
        guard enabled else { return "No action" }
        switch kind {
        case .keyboard:
            return modifierPrefix + key.title
        case .rawKeyCode:
            return modifierPrefix + "Raw(\(rawKeyCode))"
        case .media:
            return mediaKey.title
        case .shortcut:
            return shortcutName.isEmpty ? "Shortcut name is empty" : "Shortcut: \(shortcutName)"
        case .command:
            return shellCommand.isEmpty ? "Command is empty" : shellCommand
        }
    }

    func perform() {
        guard enabled else { return }
        switch kind {
        case .keyboard:
            postKeyboardEvent(keyCode: key.keyCode, modifierFlag: key.modifierFlag)
        case .rawKeyCode:
            postKeyboardEvent(keyCode: CGKeyCode(rawKeyCode), modifierFlag: nil)
        case .media:
            postMediaEvent(mediaKey)
        case .shortcut:
            guard !shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            runProcess(executable: "/usr/bin/shortcuts", arguments: ["run", shortcutName])
        case .command:
            guard !shellCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            runProcess(executable: "/bin/zsh", arguments: ["-lc", shellCommand])
        }
    }

    private var modifierPrefix: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        return parts.joined()
    }

    private var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if option { flags.insert(.maskAlternate) }
        if control { flags.insert(.maskControl) }
        if shift { flags.insert(.maskShift) }
        return flags
    }

    private func postKeyboardEvent(keyCode: CGKeyCode, modifierFlag: CGEventFlags?) {
        SynthesizedEventGuard.prepareForKeyboardOutput()

        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        var downFlags = eventFlags
        if let modifierFlag {
            downFlags.insert(modifierFlag)
        }
        down.flags = downFlags
        up.flags = eventFlags
        SynthesizedEventGuard.mark(down)
        SynthesizedEventGuard.mark(up)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func postMediaEvent(_ mediaKey: MediaKeyChoice) {
        MediaKeyEvent.post(nxKeyCode: mediaKey.nxKeyCode, isDown: true)
        MediaKeyEvent.post(nxKeyCode: mediaKey.nxKeyCode, isDown: false)
    }

    private func runProcess(executable: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

/// Posts the system-defined event macOS uses for media and special keys.
enum MediaKeyEvent {
    static func post(nxKeyCode: Int, isDown: Bool) {
        let state = isDown ? 0x0a : 0x0b
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (nxKeyCode << 16) | (state << 8),
            data2: -1
        )
        event?.cgEvent?.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
