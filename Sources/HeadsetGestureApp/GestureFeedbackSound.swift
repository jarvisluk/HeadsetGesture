import AppKit

/// The macOS system alert sounds in /System/Library/Sounds.
enum FeedbackSound: String, Codable, CaseIterable, Identifiable {
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"

    var id: String { rawValue }
    var title: String { rawValue }
}

/// The sound played for each gesture. Defaults differ per gesture so single
/// and double taps can be told apart by ear.
struct GestureSoundSet: Codable, Equatable {
    var singleTap: FeedbackSound = .morse
    var doubleTap: FeedbackSound = .pop
    var tripleTap: FeedbackSound = .tink
    var longPress: FeedbackSound = .bottle

    func sound(for gesture: RecognizedGesture) -> FeedbackSound {
        switch gesture {
        case .singleTap: return singleTap
        case .doubleTap: return doubleTap
        case .tripleTap: return tripleTap
        case .longPress: return longPress
        }
    }

    mutating func setSound(_ sound: FeedbackSound, for gesture: RecognizedGesture) {
        switch gesture {
        case .singleTap: singleTap = sound
        case .doubleTap: doubleTap = sound
        case .tripleTap: tripleTap = sound
        case .longPress: longPress = sound
        }
    }
}

/// Plays the short feedback sound for a recognized gesture or a settings preview.
@MainActor
enum GestureFeedbackSound {
    private static var cache: [FeedbackSound: NSSound] = [:]

    static func play(_ feedbackSound: FeedbackSound) {
        guard let sound = cache[feedbackSound] ?? NSSound(named: NSSound.Name(feedbackSound.rawValue)) else {
            return
        }
        cache[feedbackSound] = sound
        // Restart if the previous play of the same sound has not finished yet.
        sound.stop()
        sound.play()
    }
}
