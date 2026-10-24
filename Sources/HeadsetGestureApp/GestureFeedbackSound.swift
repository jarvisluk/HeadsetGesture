import AppKit

/// Short system sounds played when a gesture is recognized, one per gesture so
/// single and double taps can be told apart by ear.
@MainActor
enum GestureFeedbackSound {
    private static var cache: [String: NSSound] = [:]

    static func soundName(for gesture: RecognizedGesture) -> String {
        switch gesture {
        case .singleTap:
            return "Tink"
        case .doubleTap:
            return "Pop"
        case .tripleTap:
            return "Morse"
        case .longPress:
            return "Bottle"
        }
    }

    static func play(for gesture: RecognizedGesture) {
        let name = soundName(for: gesture)
        guard let sound = cache[name] ?? NSSound(named: NSSound.Name(name)) else { return }
        cache[name] = sound
        // Restart if the previous play of the same sound has not finished yet.
        sound.stop()
        sound.play()
    }
}
