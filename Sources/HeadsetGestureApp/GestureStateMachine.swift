import Foundation

enum RecognizedGesture: Equatable {
    case singleTap
    case doubleTap
    case tripleTap
    case longPress
}

struct GestureStateMachine {
    var doubleTapInterval: TimeInterval
    var longPressDuration: TimeInterval

    private(set) var isDown = false
    private var downAt: TimeInterval?
    private var lastTapUpAt: TimeInterval?
    private var completedTapCount = 0
    private var longPressWasEmitted = false
    private(set) var isAwaitingReleaseOnlyTap = false

    var hasPendingTapSequence: Bool {
        completedTapCount > 0
    }

    var pendingTapCount: Int {
        completedTapCount
    }

    func nextTapNumber(at timestamp: TimeInterval) -> Int {
        guard let lastTapUpAt,
              timestamp - lastTapUpAt <= doubleTapInterval else {
            return 1
        }
        return min(completedTapCount + 1, 3)
    }

    init(doubleTapInterval: TimeInterval, longPressDuration: TimeInterval) {
        self.doubleTapInterval = doubleTapInterval
        self.longPressDuration = longPressDuration
    }

    mutating func buttonDown(at timestamp: TimeInterval) -> [RecognizedGesture] {
        guard !isDown else { return [] }

        // A real down event is better evidence than the release-only fallback
        // armed after a stuck press timed out.
        isAwaitingReleaseOnlyTap = false

        var gestures: [RecognizedGesture] = []
        if let lastTapUpAt,
           timestamp - lastTapUpAt > doubleTapInterval,
           let pendingGesture = resolvePendingTaps() {
            gestures.append(pendingGesture)
        }

        isDown = true
        downAt = timestamp
        longPressWasEmitted = false
        return gestures
    }

    mutating func registerTap(at timestamp: TimeInterval) -> [RecognizedGesture] {
        isDown = false
        downAt = nil
        longPressWasEmitted = false
        isAwaitingReleaseOnlyTap = false

        var gestures: [RecognizedGesture] = []
        if let lastTapUpAt,
           timestamp - lastTapUpAt > doubleTapInterval,
           let pendingGesture = resolvePendingTaps() {
            gestures.append(pendingGesture)
        }

        completedTapCount += 1
        lastTapUpAt = timestamp
        if completedTapCount == 3 {
            clearPendingTaps()
            gestures.append(.tripleTap)
        }
        return gestures
    }

    mutating func longPressThresholdReached(at timestamp: TimeInterval) -> [RecognizedGesture] {
        guard isDown,
              !longPressWasEmitted,
              let downAt,
              timestamp - downAt >= longPressDuration else {
            return []
        }

        longPressWasEmitted = true
        clearPendingTaps()
        return [.longPress]
    }

    mutating func recoverStuckPress(
        at timestamp: TimeInterval,
        acceptingNextReleaseAsTap: Bool = false
    ) -> Bool {
        guard isDown,
              let downAt,
              timestamp - downAt >= longPressDuration else {
            return false
        }

        reset()
        isAwaitingReleaseOnlyTap = acceptingNextReleaseAsTap
        return true
    }

    mutating func buttonUp(at timestamp: TimeInterval) -> [RecognizedGesture] {
        guard isDown, let downAt else {
            guard isAwaitingReleaseOnlyTap else { return [] }

            // Some headsets remain logically down after losing a release. Their
            // next physical click can therefore surface only as an up event.
            // Preserve that click as the first tap in a new sequence.
            isAwaitingReleaseOnlyTap = false
            completedTapCount = 1
            lastTapUpAt = timestamp
            return []
        }
        isDown = false
        self.downAt = nil

        if longPressWasEmitted {
            longPressWasEmitted = false
            return []
        }

        if timestamp - downAt >= longPressDuration {
            clearPendingTaps()
            return [.longPress]
        }

        completedTapCount += 1
        lastTapUpAt = timestamp
        if completedTapCount == 3 {
            clearPendingTaps()
            return [.tripleTap]
        }
        return []
    }

    mutating func tapSequenceThresholdReached(at timestamp: TimeInterval) -> [RecognizedGesture] {
        guard !isDown,
              let lastTapUpAt,
              timestamp - lastTapUpAt >= doubleTapInterval,
              let gesture = resolvePendingTaps() else {
            return []
        }
        return [gesture]
    }

    mutating func reset() {
        isDown = false
        downAt = nil
        clearPendingTaps()
        longPressWasEmitted = false
        isAwaitingReleaseOnlyTap = false
    }

    private mutating func resolvePendingTaps() -> RecognizedGesture? {
        let gesture: RecognizedGesture?
        switch completedTapCount {
        case 1:
            gesture = .singleTap
        case 2:
            gesture = .doubleTap
        default:
            gesture = nil
        }
        clearPendingTaps()
        return gesture
    }

    private mutating func clearPendingTaps() {
        completedTapCount = 0
        lastTapUpAt = nil
    }
}
