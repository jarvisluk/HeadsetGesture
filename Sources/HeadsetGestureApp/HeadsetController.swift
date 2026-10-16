import ApplicationServices
import AppKit
import CoreGraphics
import Darwin
import Foundation
import IOKit.hid
import IOKit.hidsystem
import OSLog

private let gestureDiagnosticLogger = Logger(
    subsystem: "local.codex.HeadsetGesture",
    category: "GestureDiagnostics"
)

private enum HIDTimestamp {
    static let secondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()

    static func seconds(_ absoluteTime: UInt64) -> TimeInterval {
        Double(absoluteTime) * secondsPerTick
    }
}

@MainActor
final class HeadsetController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isConnected = false
    @Published private(set) var statusText = "Not started"
    @Published private(set) var lastGestureText = "No gesture yet"
    @Published private(set) var inputMonitoringGranted = HeadsetController.hasInputMonitoringAccess
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var isHeadsetButtonPressed = false
    @Published private(set) var currentInputSignalText = "No key pressed"
    @Published private(set) var gesturePreviewText = "Idle"
    @Published private(set) var mappedOutputPreviewText = "No output yet"
    @Published private(set) var lastRawInputValue = 0
    @Published private(set) var pressBeganAt: TimeInterval?
    @Published private(set) var inputEvents: [LiveInputEvent] = []
    @Published private(set) var gestureDiagnosticSummaryText = "No completed samples"
    @Published private(set) var lastGestureDiagnosticText = "Make several short clicks to collect timing data."

    var inputMonitoringStatusText: String {
        guard inputMonitoringGranted else { return "Not granted" }
        return accessibilityGranted && !Self.hasDirectInputMonitoringAccess
            ? "Granted via Accessibility"
            : "Granted"
    }

    private let settings: SettingsStore
    private let longPressDurationOverlay: LongPressDurationOverlayController
    private var manager: IOHIDManager?
    private var stateMachine: GestureStateMachine
    private var tapSequenceWorkItem: DispatchWorkItem?
    private var longPressWorkItem: DispatchWorkItem?
    private var stuckPressWorkItem: DispatchWorkItem?
    private var inputEventSequence = 0
    private var pressSequence = 0
    private var activePressDiagnostic: ActivePressDiagnostic?
    private var normalDiagnosticCount = 0
    private var appDelayDiagnosticCount = 0
    private var inputHeldDiagnosticCount = 0
    private var lastTapOnlyActivationAt: TimeInterval?
    private var connectedDeviceCount = 0
    private var lastDeviceAddedAt: TimeInterval?
    /// Whether the most recent Play/Pause report was a press. A release that
    /// follows another release means the headset dropped the press report.
    private var lastPlayPauseReportWasPress = false
    private var permissionPollTimer: Timer?

    private static let releaseConfirmationWindow: TimeInterval = 1.0
    private static let tapOnlyDebounceInterval: TimeInterval = 0.08
    private static let permissionPollInterval: TimeInterval = 2.0
    /// Reports right after a device attaches can be leftover state, not clicks.
    private static let deviceAttachGracePeriod: TimeInterval = 0.5

    private struct ActivePressDiagnostic {
        let sequence: Int
        let inputDownAt: TimeInterval
        let callbackDownAt: TimeInterval
        let longPressThreshold: TimeInterval
        let longPressTriggerMode: LongPressTriggerMode
        var longPressThresholdReached = false
        var longPressWasEmittedImmediately = false
    }

    init(
        settings: SettingsStore,
        longPressDurationOverlay: LongPressDurationOverlayController
    ) {
        self.settings = settings
        self.longPressDurationOverlay = longPressDurationOverlay
        stateMachine = GestureStateMachine(
            doubleTapInterval: settings.doubleTapInterval,
            longPressDuration: settings.longPressDuration
        )
        gestureDiagnosticLogger.info("event=diagnostics_ready")
        updatePermissionPolling()
    }

    func start() {
        guard manager == nil else { return }
        refreshPermissionStatus()

        let newManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDProductKey as String: "Headset",
            kIOHIDPrimaryUsagePageKey as String: 0x0c
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerSetDeviceMatching(newManager, matching as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(newManager, Self.deviceAddedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(newManager, Self.deviceRemovedCallback, context)
        IOHIDManagerRegisterInputValueCallback(newManager, Self.valueCallback, context)
        IOHIDManagerScheduleWithRunLoop(
            newManager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        let result = IOHIDManagerOpen(newManager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(
                newManager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            inputMonitoringGranted = false
            updatePermissionPolling()
            isRunning = false
            isConnected = false
            statusText = result == kIOReturnNotPermitted
                ? "Input Monitoring permission required"
                : String(format: "Failed to start: 0x%08x", UInt32(bitPattern: result))
            return
        }

        inputMonitoringGranted = Self.hasInputMonitoringAccess
        guard inputMonitoringGranted else {
            IOHIDManagerUnscheduleFromRunLoop(
                newManager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            IOHIDManagerClose(newManager, IOOptionBits(kIOHIDOptionsTypeNone))
            isRunning = false
            isConnected = false
            statusText = "Input Monitoring permission required"
            return
        }

        manager = newManager
        isRunning = true
        statusText = "Waiting for Headset"
    }

    func stop() {
        tapSequenceWorkItem?.cancel()
        tapSequenceWorkItem = nil
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        stuckPressWorkItem?.cancel()
        stuckPressWorkItem = nil
        stateMachine.reset()
        resetCurrentInputPreview(status: "Monitoring stopped")

        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        manager = nil
        connectedDeviceCount = 0
        isRunning = false
        isConnected = false
        statusText = "Interception disabled"
    }

    func applyEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    func requestInputMonitoringPermission() {
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        inputMonitoringGranted = granted || Self.hasInputMonitoringAccess
        openPrivacySettings(pane: "Privacy_ListenEvent")
        refreshPermissionStatus()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermissionStatus()
    }

    func reconnect() {
        stop()
        start()
    }

    func refreshPermissionStatus() {
        let previouslyGranted = inputMonitoringGranted
        inputMonitoringGranted = Self.hasInputMonitoringAccess
        accessibilityGranted = AXIsProcessTrusted()
        if isConnected {
            statusText = connectedStatusText
        }

        if !previouslyGranted, inputMonitoringGranted, settings.enabled, manager == nil {
            start()
        }
        updatePermissionPolling()
    }

    /// Permissions are granted in System Settings while this app is in the
    /// background, and macOS sends no reliable notification for them. Poll only
    /// while something is missing so the menu bar state and the HID connection
    /// recover on their own.
    private func updatePermissionPolling() {
        let needsPolling = !inputMonitoringGranted || !accessibilityGranted
        guard needsPolling != (permissionPollTimer != nil) else { return }

        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
        guard needsPolling else { return }

        let timer = Timer(timeInterval: Self.permissionPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPermissionsAndReconnectIfNeeded()
            }
        }
        timer.tolerance = 0.5
        permissionPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func refreshPermissionsAndReconnectIfNeeded() {
        refreshPermissionStatus()
        if settings.enabled, manager == nil {
            start()
        }
    }

    func restartApp() {
        // Info.plist sets LSMultipleInstancesProhibited, so asking LaunchServices for a
        // new instance while this one is alive only re-activates it, and terminating
        // afterwards would leave the app closed. Hand the relaunch to a detached shell
        // that waits for this process to exit first.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            // LaunchServices briefly keeps the exited app registered (error -600),
            // so retry the open for a few seconds.
            """
            while kill -0 "$1" 2>/dev/null; do sleep 0.1; done
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                sleep 0.3
                /usr/bin/open "$2" && exit 0
            done
            exit 1
            """,
            "relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundleURL.path
        ]
        do {
            try process.run()
        } catch {
            statusText = "Could not restart the app"
            return
        }
        NSApp.terminate(nil)
    }

    func clearInputPreview() {
        inputEvents.removeAll()
        inputEventSequence = 0
        normalDiagnosticCount = 0
        appDelayDiagnosticCount = 0
        inputHeldDiagnosticCount = 0
        gestureDiagnosticSummaryText = "No completed samples"
        lastGestureDiagnosticText = "Make several short clicks to collect timing data."
        mappedOutputPreviewText = "No output yet"
        if !isHeadsetButtonPressed {
            currentInputSignalText = "No key pressed"
            gesturePreviewText = isRunning ? "Idle" : "Monitoring stopped"
            lastRawInputValue = 0
        }
    }

    private static var hasInputMonitoringAccess: Bool {
        AXIsProcessTrusted() || hasDirectInputMonitoringAccess
    }

    private static var hasDirectInputMonitoringAccess: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
            || CGPreflightListenEventAccess()
    }

    private func openPrivacySettings(pane: String) {
        let modernURL = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)"
        )
        if let modernURL, NSWorkspace.shared.open(modernURL) {
            return
        }

        if let legacyURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) {
            NSWorkspace.shared.open(legacyURL)
        }
    }

    private func deviceAdded(_ device: IOHIDDevice) {
        connectedDeviceCount += 1
        lastDeviceAddedAt = ProcessInfo.processInfo.systemUptime
        isConnected = true
        statusText = connectedStatusText
    }

    private var connectedStatusText: String {
        accessibilityGranted
            ? "Headset connected and intercepted"
            : "Intercepting; Accessibility permission required to send keys"
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        connectedDeviceCount = max(0, connectedDeviceCount - 1)
        // Another matching "Headset" interface may still be attached.
        guard connectedDeviceCount == 0 else { return }
        isConnected = false
        statusText = "Headset disconnected"
        tapSequenceWorkItem?.cancel()
        tapSequenceWorkItem = nil
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        stuckPressWorkItem?.cancel()
        stuckPressWorkItem = nil
        stateMachine.reset()
        resetCurrentInputPreview(status: "Device disconnected")
    }

    private func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let timestamp = ProcessInfo.processInfo.systemUptime
        let inputTimestamp = HIDTimestamp.seconds(IOHIDValueGetTimeStamp(value))
        let rawValue = Int(IOHIDValueGetIntegerValue(value))

        // Log every report, including usages ignored below, so presses that land
        // on another usage (for example an off-center press) are visible.
        let usageText = String(format: "0x%02X/0x%04X", page, usage)
        let rawText = String(format: "%.4f", inputTimestamp)
        let rawDelayText = String(format: "%.1f", max(0, timestamp - inputTimestamp) * 1_000)
        gestureDiagnosticLogger.info(
            "event=raw usage=\(usageText, privacy: .public) value=\(rawValue, privacy: .public) input_ts=\(rawText, privacy: .public) delivery_ms=\(rawDelayText, privacy: .public)"
        )
        guard page == 0x0c, usage == 0x00cd else { return }

        stateMachine.doubleTapInterval = settings.doubleTapInterval
        stateMachine.longPressDuration = settings.longPressDuration
        let isPressed = rawValue != 0
        let isReleaseWithoutPress = !isPressed
            && !lastPlayPauseReportWasPress
            && !isWithinDeviceAttachGracePeriod(inputTimestamp)
        lastPlayPauseReportWasPress = isPressed

        isHeadsetButtonPressed = isPressed
        currentInputSignalText = isPressed
            ? "Consumer Play/Pause (0xCD)"
            : "No key pressed"
        lastRawInputValue = rawValue
        if isReleaseWithoutPress {
            handleReleaseWithoutPress(rawValue: rawValue, inputTimestamp: inputTimestamp)
            return
        }

        if !settings.longPressRecognitionEnabled {
            handleTapOnlySignal(
                isPressed: isPressed,
                rawValue: rawValue,
                inputTimestamp: inputTimestamp
            )
            return
        }

        if isPressed {
            if stateMachine.isDown {
                guard stateMachine.recoverStuckPress(at: inputTimestamp) else {
                    recordInputEvent(
                        kind: .press,
                        title: "Repeated press",
                        detail: String(format: "Consumer 0xCD · raw value %d", rawValue)
                    )
                    gestureDiagnosticLogger.info("event=repeated_down action=ignored")
                    return
                }
                longPressWorkItem?.cancel()
                longPressWorkItem = nil
                stuckPressWorkItem?.cancel()
                stuckPressWorkItem = nil
                recordStuckPressRecovery(recoveredAt: inputTimestamp, newPressWasPreserved: true)
            }
            pressSequence += 1
            activePressDiagnostic = ActivePressDiagnostic(
                sequence: pressSequence,
                inputDownAt: inputTimestamp,
                callbackDownAt: timestamp,
                longPressThreshold: settings.longPressDuration,
                longPressTriggerMode: settings.longPressTriggerMode
            )
            let deliveryMilliseconds = max(0, timestamp - inputTimestamp) * 1_000
            let deliveryText = String(format: "%.1f", deliveryMilliseconds)
            let thresholdText = String(format: "%.0f", settings.longPressDuration * 1_000)
            recordInputEvent(
                kind: .press,
                title: "Pressed",
                detail: String(
                    format: "Sample #%d · input delivery %.1f ms",
                    pressSequence,
                    deliveryMilliseconds
                )
            )
            gestureDiagnosticLogger.info(
                "sample=\(self.pressSequence, privacy: .public) event=down input_delivery_ms=\(deliveryText, privacy: .public) threshold_ms=\(thresholdText, privacy: .public)"
            )

            let tapNumber = stateMachine.nextTapNumber(at: inputTimestamp)
            tapSequenceWorkItem?.cancel()
            tapSequenceWorkItem = nil
            pressBeganAt = timestamp
            switch tapNumber {
            case 2:
                gesturePreviewText = "Second tap pressed"
            case 3:
                gesturePreviewText = "Third tap pressed"
            default:
                gesturePreviewText = "Holding…"
            }
            emit(stateMachine.buttonDown(at: inputTimestamp))
            longPressDurationOverlay.begin(
                at: timestamp,
                threshold: settings.longPressDuration
            )
            scheduleLongPress(after: settings.longPressDuration)
        } else {
            longPressDurationOverlay.end()
            pressBeganAt = nil
            longPressWorkItem?.cancel()
            longPressWorkItem = nil
            stuckPressWorkItem?.cancel()
            stuckPressWorkItem = nil
            let recoveredReleaseOnlyTap = stateMachine.isAwaitingReleaseOnlyTap
            let gestures = stateMachine.buttonUp(at: inputTimestamp)
            if recoveredReleaseOnlyTap {
                recordRecoveredReleaseOnlyTap()
            } else {
                recordReleaseDiagnostic(
                    inputUpAt: inputTimestamp,
                    callbackUpAt: timestamp,
                    releaseGestures: gestures
                )
            }
            emit(gestures)
            if stateMachine.hasPendingTapSequence {
                gesturePreviewText = stateMachine.pendingTapCount == 1
                    ? "Waiting for second tap"
                    : "Waiting for third tap"
                scheduleTapSequenceResolution(after: settings.doubleTapInterval)
            } else if gestures.isEmpty, gesturePreviewText != "Long press recognized" {
                gesturePreviewText = "Released"
            }
        }
    }

    private func handleTapOnlySignal(
        isPressed: Bool,
        rawValue: Int,
        inputTimestamp: TimeInterval
    ) {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        stuckPressWorkItem?.cancel()
        stuckPressWorkItem = nil
        longPressDurationOverlay.end()
        pressBeganAt = nil
        activePressDiagnostic = nil
        isHeadsetButtonPressed = false

        guard isPressed else {
            if stateMachine.isDown || stateMachine.isAwaitingReleaseOnlyTap {
                stateMachine.reset()
            }
            currentInputSignalText = "No key pressed"
            recordInputEvent(
                kind: .release,
                title: "Released",
                detail: "Tap-only mode · release not required"
            )
            return
        }

        guard registerTap(at: inputTimestamp) else {
            gestureDiagnosticLogger.info("event=tap_only_down action=debounced")
            return
        }
        currentInputSignalText = "Tap pulse accepted"
        recordInputEvent(
            kind: .press,
            title: "Tap pulse",
            detail: String(format: "Tap-only mode · raw value %d", rawValue)
        )
        lastGestureDiagnosticText = "Tap-only mode: the press pulse was accepted without waiting for release."
        gestureDiagnosticLogger.info("event=tap_only_down action=accepted")
    }

    /// The headset sometimes drops the press report of a click and only sends the
    /// release. Count that release as the tap instead of losing the click.
    private func handleReleaseWithoutPress(rawValue: Int, inputTimestamp: TimeInterval) {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        stuckPressWorkItem?.cancel()
        stuckPressWorkItem = nil
        longPressDurationOverlay.end()
        pressBeganAt = nil
        activePressDiagnostic = nil
        isHeadsetButtonPressed = false
        currentInputSignalText = "No key pressed"

        guard registerTap(at: inputTimestamp) else {
            gestureDiagnosticLogger.info("event=release_without_press action=debounced")
            return
        }
        recordInputEvent(
            kind: .press,
            title: "Recovered tap",
            detail: String(format: "Press report missing · counted from release (raw %d)", rawValue)
        )
        lastGestureDiagnosticText = "The headset sent a release without a press; it was counted as a tap."
        gestureDiagnosticLogger.info("event=release_without_press action=counted_as_tap")
    }

    /// Feeds one tap into the sequence recognizer. Returns false when the tap is
    /// rejected as contact bounce of the previous one.
    private func registerTap(at inputTimestamp: TimeInterval) -> Bool {
        if let lastTapOnlyActivationAt,
           inputTimestamp - lastTapOnlyActivationAt < Self.tapOnlyDebounceInterval {
            return false
        }
        lastTapOnlyActivationAt = inputTimestamp

        tapSequenceWorkItem?.cancel()
        tapSequenceWorkItem = nil
        emit(stateMachine.registerTap(at: inputTimestamp))
        if stateMachine.hasPendingTapSequence {
            gesturePreviewText = stateMachine.pendingTapCount == 1
                ? "Waiting for second tap"
                : "Waiting for third tap"
            scheduleTapSequenceResolution(after: settings.doubleTapInterval)
        }
        return true
    }

    private func isWithinDeviceAttachGracePeriod(_ inputTimestamp: TimeInterval) -> Bool {
        guard let lastDeviceAddedAt else { return false }
        return inputTimestamp - lastDeviceAddedAt < Self.deviceAttachGracePeriod
    }

    private func scheduleTapSequenceResolution(after delay: TimeInterval) {
        tapSequenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let gestures = self.stateMachine.tapSequenceThresholdReached(
                at: ProcessInfo.processInfo.systemUptime
            )
            self.tapSequenceWorkItem = nil
            self.emit(gestures)
        }
        tapSequenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleLongPress(after delay: TimeInterval) {
        longPressWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let timestamp = ProcessInfo.processInfo.systemUptime
            self.longPressWorkItem = nil
            if self.stateMachine.isDown {
                self.activePressDiagnostic?.longPressThresholdReached = true
                if let sample = self.activePressDiagnostic {
                    switch sample.longPressTriggerMode {
                    case .onRelease:
                        self.gesturePreviewText = "Release to confirm long press"
                        self.scheduleStuckPressRecovery(
                            for: sample.sequence,
                            after: Self.releaseConfirmationWindow
                        )
                    case .immediately:
                        let gestures = self.stateMachine.longPressThresholdReached(at: timestamp)
                        self.activePressDiagnostic?.longPressWasEmittedImmediately = gestures.contains(.longPress)
                        self.emit(gestures)
                    }

                    let callbackHoldMilliseconds = (timestamp - sample.callbackDownAt) * 1_000
                    let callbackHoldText = String(format: "%.1f", callbackHoldMilliseconds)
                    gestureDiagnosticLogger.info(
                        "sample=\(sample.sequence, privacy: .public) event=long_press_threshold mode=\(sample.longPressTriggerMode.rawValue, privacy: .public) callback_hold_ms=\(callbackHoldText, privacy: .public)"
                    )
                }
            }
        }
        longPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleStuckPressRecovery(for sampleSequence: Int, after delay: TimeInterval) {
        stuckPressWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.activePressDiagnostic?.sequence == sampleSequence,
                  self.stateMachine.isDown else {
                return
            }

            let timestamp = ProcessInfo.processInfo.systemUptime
            guard self.stateMachine.recoverStuckPress(
                at: timestamp,
                acceptingNextReleaseAsTap: true
            ) else { return }

            self.stuckPressWorkItem = nil
            self.longPressDurationOverlay.end()
            self.pressBeganAt = nil
            self.isHeadsetButtonPressed = false
            self.currentInputSignalText = "No key pressed (recovered)"
            self.lastRawInputValue = 0
            self.gesturePreviewText = "Missing release; input reset"
            self.recordStuckPressRecovery(
                recoveredAt: timestamp,
                newPressWasPreserved: false
            )
        }
        stuckPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func recordStuckPressRecovery(
        recoveredAt: TimeInterval,
        newPressWasPreserved: Bool
    ) {
        guard let sample = activePressDiagnostic else { return }
        activePressDiagnostic = nil

        let heldMilliseconds = max(0, recoveredAt - sample.inputDownAt) * 1_000
        inputHeldDiagnosticCount += 1
        refreshDiagnosticSummary()
        if newPressWasPreserved {
            lastGestureDiagnosticText = String(
                format: "Sample #%d: missing release recovered after %.0f ms; the new press was preserved.",
                sample.sequence,
                heldMilliseconds
            )
        } else {
            lastGestureDiagnosticText = String(
                format: "Sample #%d: missing release timed out after %.0f ms; the input state was reset.",
                sample.sequence,
                heldMilliseconds
            )
        }
        recordInputEvent(
            kind: .release,
            title: "Recovered input",
            detail: String(
                format: "#%d · missing release · held %.0f ms · %@",
                sample.sequence,
                heldMilliseconds,
                newPressWasPreserved ? "new press preserved" : "automatic reset"
            )
        )

        let heldText = String(format: "%.1f", heldMilliseconds)
        let recoveryText = newPressWasPreserved ? "new_press" : "timeout"
        gestureDiagnosticLogger.info(
            "sample=\(sample.sequence, privacy: .public) event=stuck_press_recovered reason=\(recoveryText, privacy: .public) input_held_ms=\(heldText, privacy: .public)"
        )
    }

    private func recordReleaseDiagnostic(
        inputUpAt: TimeInterval,
        callbackUpAt: TimeInterval,
        releaseGestures: [RecognizedGesture]
    ) {
        guard let sample = activePressDiagnostic else {
            recordInputEvent(kind: .release, title: "Released", detail: "No matching press sample")
            gestureDiagnosticLogger.info("event=up result=unmatched_release")
            return
        }
        activePressDiagnostic = nil

        let diagnostic = GestureTimingDiagnostic(
            inputHoldDuration: max(0, inputUpAt - sample.inputDownAt),
            callbackHoldDuration: max(0, callbackUpAt - sample.callbackDownAt),
            longPressThreshold: sample.longPressThreshold,
            longPressWasEmitted: sample.longPressWasEmittedImmediately || releaseGestures.contains(.longPress)
        )
        updateDiagnosticCounts(for: diagnostic.verdict)

        let inputMilliseconds = diagnostic.inputHoldDuration * 1_000
        let callbackMilliseconds = diagnostic.callbackHoldDuration * 1_000
        let delayMilliseconds = diagnostic.releaseProcessingDelay * 1_000
        let verdictText: String
        switch diagnostic.verdict {
        case .normal:
            verdictText = "Normal"
            lastGestureDiagnosticText = String(
                format: "Sample #%d: input held %.0f ms; timing was normal.",
                sample.sequence,
                inputMilliseconds
            )
        case .appProcessingDelay:
            verdictText = "App processing delay"
            lastGestureDiagnosticText = String(
                format: "Sample #%d: input held only %.0f ms, but release processing lagged by %.0f ms.",
                sample.sequence,
                inputMilliseconds,
                delayMilliseconds
            )
        case .inputSignalHeld:
            verdictText = "Input signal held"
            lastGestureDiagnosticText = String(
                format: "Sample #%d: the HID signal stayed pressed for %.0f ms (threshold %.0f ms).",
                sample.sequence,
                inputMilliseconds,
                sample.longPressThreshold * 1_000
            )
        }

        recordInputEvent(
            kind: .release,
            title: "Released",
            detail: String(
                format: "#%d · input %.0f ms · callback %.0f ms · %@",
                sample.sequence,
                inputMilliseconds,
                callbackMilliseconds,
                verdictText
            )
        )

        let inputText = String(format: "%.1f", inputMilliseconds)
        let callbackText = String(format: "%.1f", callbackMilliseconds)
        let delayText = String(format: "%.1f", delayMilliseconds)
        let thresholdText = String(format: "%.0f", sample.longPressThreshold * 1_000)
        let longPressText = diagnostic.longPressWasEmitted ? "true" : "false"
        let thresholdReachedText = sample.longPressThresholdReached ? "true" : "false"
        gestureDiagnosticLogger.info(
            "sample=\(sample.sequence, privacy: .public) event=up verdict=\(diagnostic.verdict.rawValue, privacy: .public) input_hold_ms=\(inputText, privacy: .public) callback_hold_ms=\(callbackText, privacy: .public) release_processing_delay_ms=\(delayText, privacy: .public) threshold_ms=\(thresholdText, privacy: .public) long_press_emitted=\(longPressText, privacy: .public) threshold_reached=\(thresholdReachedText, privacy: .public)"
        )
    }

    private func recordRecoveredReleaseOnlyTap() {
        recordInputEvent(
            kind: .release,
            title: "Recovered click",
            detail: "Release-only signal accepted as a new tap after timeout"
        )
        gestureDiagnosticLogger.info(
            "event=up result=recovered_release_only_tap"
        )
    }

    private func updateDiagnosticCounts(for verdict: GestureTimingVerdict) {
        switch verdict {
        case .normal:
            normalDiagnosticCount += 1
        case .appProcessingDelay:
            appDelayDiagnosticCount += 1
        case .inputSignalHeld:
            inputHeldDiagnosticCount += 1
        }

        refreshDiagnosticSummary()
    }

    private func refreshDiagnosticSummary() {
        let total = normalDiagnosticCount + appDelayDiagnosticCount + inputHeldDiagnosticCount
        gestureDiagnosticSummaryText = "\(total) samples · normal \(normalDiagnosticCount) · input held \(inputHeldDiagnosticCount) · app delay \(appDelayDiagnosticCount)"
    }

    private func emit(_ gestures: [RecognizedGesture]) {
        for gesture in gestures {
            gestureDiagnosticLogger.info("event=gesture type=\(String(describing: gesture), privacy: .public)")
            switch gesture {
            case .singleTap:
                let output = settings.singleTapAction.summary
                lastGestureText = "Single tap → \(output)"
                gesturePreviewText = "Single tap recognized"
                mappedOutputPreviewText = output
                recordInputEvent(kind: .gesture, title: "Single tap", detail: "Output → \(output)")
                settings.singleTapAction.perform()
            case .doubleTap:
                let output = settings.doubleTapAction.summary
                lastGestureText = "Double tap → \(output)"
                gesturePreviewText = "Double tap recognized"
                mappedOutputPreviewText = output
                recordInputEvent(kind: .gesture, title: "Double tap", detail: "Output → \(output)")
                settings.doubleTapAction.perform()
            case .tripleTap:
                let output = settings.tripleTapAction.summary
                lastGestureText = "Triple tap → \(output)"
                gesturePreviewText = "Triple tap recognized"
                mappedOutputPreviewText = output
                recordInputEvent(kind: .gesture, title: "Triple tap", detail: "Output → \(output)")
                settings.tripleTapAction.perform()
            case .longPress:
                let output = settings.longPressAction.summary
                lastGestureText = "Long press → \(output)"
                gesturePreviewText = "Long press recognized"
                mappedOutputPreviewText = output
                recordInputEvent(kind: .gesture, title: "Long press", detail: "Output → \(output)")
                settings.longPressAction.perform()
            }
        }
    }

    private func recordInputEvent(kind: LiveInputEvent.Kind, title: String, detail: String) {
        inputEventSequence += 1
        inputEvents.insert(
            LiveInputEvent(
                sequence: inputEventSequence,
                kind: kind,
                title: title,
                detail: detail,
                occurredAt: Date()
            ),
            at: 0
        )
        if inputEvents.count > 8 {
            inputEvents.removeLast(inputEvents.count - 8)
        }
    }

    private func resetCurrentInputPreview(status: String) {
        stuckPressWorkItem?.cancel()
        stuckPressWorkItem = nil
        longPressDurationOverlay.end()
        activePressDiagnostic = nil
        lastTapOnlyActivationAt = nil
        lastPlayPauseReportWasPress = false
        isHeadsetButtonPressed = false
        currentInputSignalText = "No key pressed"
        gesturePreviewText = status
        lastRawInputValue = 0
        pressBeganAt = nil
    }

    nonisolated private static let deviceAddedCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let owner = Unmanaged<HeadsetController>.fromOpaque(context).takeUnretainedValue()
        // The HID manager is scheduled on the main run loop, so preserve callback order
        // instead of introducing another asynchronous hop onto the main actor.
        MainActor.assumeIsolated {
            owner.deviceAdded(device)
        }
    }

    nonisolated private static let deviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let owner = Unmanaged<HeadsetController>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated {
            owner.deviceRemoved(device)
        }
    }

    nonisolated private static let valueCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        let owner = Unmanaged<HeadsetController>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated {
            owner.handle(value: value)
        }
    }
}
