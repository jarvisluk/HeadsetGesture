import Foundation

enum GestureTimingVerdict: String, Equatable {
    case normal = "normal"
    case appProcessingDelay = "app_processing_delay"
    case inputSignalHeld = "input_signal_held"
}

struct GestureTimingDiagnostic: Equatable {
    let inputHoldDuration: TimeInterval
    let callbackHoldDuration: TimeInterval
    let longPressThreshold: TimeInterval
    let longPressWasEmitted: Bool

    var releaseProcessingDelay: TimeInterval {
        max(0, callbackHoldDuration - inputHoldDuration)
    }

    var verdict: GestureTimingVerdict {
        if inputHoldDuration >= longPressThreshold {
            return .inputSignalHeld
        }
        if longPressWasEmitted {
            return .appProcessingDelay
        }
        return .normal
    }
}
