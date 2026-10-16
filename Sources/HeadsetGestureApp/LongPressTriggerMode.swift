import Foundation

enum LongPressTriggerMode: String, CaseIterable, Identifiable {
    case onRelease
    case immediately

    var id: Self { self }

    var title: String {
        switch self {
        case .onRelease:
            return "On Release"
        case .immediately:
            return "Immediately"
        }
    }

    var guidance: String {
        switch self {
        case .onRelease:
            return "Recommended when the headset may occasionally miss release events. The action runs after you let go. If no release arrives within 1 second after the threshold, the press is cancelled and reset."
        case .immediately:
            return "Runs as soon as the duration is reached. Use this when the headset reports releases reliably and immediate response matters; a missing release can still cause a false long press."
        }
    }
}
