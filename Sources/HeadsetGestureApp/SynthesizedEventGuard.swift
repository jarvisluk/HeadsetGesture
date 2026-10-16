import AppKit
import CoreGraphics

enum SynthesizedEventGuard {
    private static let eventMarker: Int64 = 0x48475354

    static func prepareForKeyboardOutput() {
        guard NSApp.isActive else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    static func mark(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
    }

    static func shouldSuppressInsideApp(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == eventMarker
    }
}
