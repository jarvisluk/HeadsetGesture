import ApplicationServices
import AppKit
import CoreGraphics
import Darwin
import Foundation
import IOKit.hid
import IOKit.hidsystem
import OSLog

private let gestureDiagnosticLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "io.github.jarvisluk.HeadsetGesture",
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
    @Published private(set) var lastInputButton: HeadsetButton = .playPause
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
    /// Devices this app has seized. The manager itself is never opened, so
    /// matched devices that are not headsets stay untouched.
    private var openedDevices: [IOHIDDevice] = []
    /// Headsets whose open was refused for missing Input Monitoring. The
    /// permission poll retries them, since the manager never matches them again.
    private var permissionDeniedDevices: [IOHIDDevice] = []
    private let channels: [HeadsetButton: ButtonChannel]
    private var inputEventSequence = 0
    private var pressSequence = 0
    private var normalDiagnosticCount = 0
    private var appDelayDiagnosticCount = 0
    private var inputHeldDiagnosticCount = 0
    private var lastDeviceAddedAt: TimeInterval?
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

    /// Recognition state of one physical button. Each button has its own
    /// gesture sequence, so a volume press never completes a Play/Pause double tap.
    private final class ButtonChannel {
        let button: HeadsetButton
        var stateMachine: GestureStateMachine
        var tapSequenceWorkItem: DispatchWorkItem?
        var longPressWorkItem: DispatchWorkItem?
        var stuckPressWorkItem: DispatchWorkItem?
        var activePressDiagnostic: ActivePressDiagnostic?
        var lastTapOnlyActivationAt: TimeInterval?
        /// Whether the most recent report was a press. A release that follows
        /// another release means the headset dropped the press report.
        var lastReportWasPress = false

        init(button: HeadsetButton, stateMachine: GestureStateMachine) {
            self.button = button
            self.stateMachine = stateMachine
        }

        func cancelTimers() {
            tapSequenceWorkItem?.cancel()
            tapSequenceWorkItem = nil
            cancelPressTimers()
        }

        func cancelPressTimers() {
            longPressWorkItem?.cancel()
            longPressWorkItem = nil
            stuckPressWorkItem?.cancel()
            stuckPressWorkItem = nil
        }
    }

    init(
        settings: SettingsStore,
        longPressDurationOverlay: LongPressDurationOverlayController
    ) {
        self.settings = settings
        self.longPressDurationOverlay = longPressDurationOverlay
        var channels: [HeadsetButton: ButtonChannel] = [:]
        for button in HeadsetButton.allCases {
            channels[button] = ButtonChannel(
                button: button,
                stateMachine: GestureStateMachine(
                    doubleTapInterval: settings.doubleTapInterval,
                    longPressDuration: settings.longPressDuration
                )
            )
        }
        self.channels = channels
        gestureDiagnosticLogger.info("event=diagnostics_ready")
        updatePermissionPolling()
    }

    func start() {
        guard manager == nil else { return }
        refreshPermissionStatus()

        guard inputMonitoringGranted else {
            isRunning = false
            isConnected = false
            statusText = "Input Monitoring permission required"
            return
        }

        let newManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerSetDeviceMatchingMultiple(
            newManager,
            HeadsetDeviceFilter.matchingDictionaries as CFArray
        )
        IOHIDManagerRegisterDeviceMatchingCallback(newManager, Self.deviceAddedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(newManager, Self.deviceRemovedCallback, context)
        IOHIDManagerScheduleWithRunLoop(
            newManager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        manager = newManager
        isRunning = true
        statusText = "Waiting for Headset"
    }

    func stop() {
        for channel in channels.values {
            channel.cancelTimers()
            channel.stateMachine.reset()
        }
        resetCurrentInputPreview(status: "Monitoring stopped")

        for device in openedDevices {
            close(device)
        }
        openedDevices.removeAll()
        permissionDeniedDevices.removeAll()

        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
        }

        manager = nil
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
        retryPermissionDeniedDevices()
        // Accessibility alone passes `hasInputMonitoringAccess`, but seizing a
        // device can still be refused; that refusal is the authoritative answer.
        inputMonitoringGranted = Self.hasInputMonitoringAccess && permissionDeniedDevices.isEmpty
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
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        // A device matching both dictionaries can arrive as two IOHIDDevice
        // objects for the same service; the second open would fail as exclusive.
        let service = IOHIDDeviceGetService(device)
        guard !openedDevices.contains(where: { $0 === device || IOHIDDeviceGetService($0) == service }) else {
            return
        }
        guard HeadsetDeviceFilter.shouldIntercept(device) else {
            gestureDiagnosticLogger.info("event=device_skipped product=\(product, privacy: .public)")
            return
        }

        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            let resultText = String(format: "0x%08x", UInt32(bitPattern: result))
            gestureDiagnosticLogger.info(
                "event=device_open_failed product=\(product, privacy: .public) result=\(resultText, privacy: .public)"
            )
            if result == kIOReturnNotPermitted {
                if !permissionDeniedDevices.contains(where: { $0 === device }) {
                    permissionDeniedDevices.append(device)
                }
                inputMonitoringGranted = false
                updatePermissionPolling()
                statusText = "Input Monitoring permission required"
            } else if openedDevices.isEmpty {
                statusText = "Could not open \(product): \(resultText)"
            }
            return
        }

        IOHIDDeviceRegisterInputValueCallback(
            device,
            Self.valueCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        openedDevices.append(device)
        gestureDiagnosticLogger.info("event=device_opened product=\(product, privacy: .public)")

        lastDeviceAddedAt = ProcessInfo.processInfo.systemUptime
        isConnected = true
        statusText = connectedStatusText
    }

    private func retryPermissionDeniedDevices() {
        guard manager != nil, !permissionDeniedDevices.isEmpty else { return }
        let devices = permissionDeniedDevices
        permissionDeniedDevices.removeAll()
        // A device refused again is put back by `deviceAdded`.
        devices.forEach(deviceAdded)
    }

    private func close(_ device: IOHIDDevice) {
        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private var connectedStatusText: String {
        accessibilityGranted
            ? "Headset connected and intercepted"
            : "Intercepting; Accessibility permission required to send keys"
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        permissionDeniedDevices.removeAll { $0 === device }
        guard let index = openedDevices.firstIndex(where: { $0 === device }) else { return }
        openedDevices.remove(at: index)
        // Another headset may still be attached.
        guard openedDevices.isEmpty else { return }
        isConnected = false
        statusText = "Headset disconnected"
        for channel in channels.values {
            channel.cancelTimers()
            channel.stateMachine.reset()
        }
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
        if let nxKeyCode = ConsumerKeyPassthrough.nxKeyCode(usagePage: page, usage: usage) {
            let isPressed = rawValue != 0
            // A press right after attach can be leftover state; forwarding it
            // would, for example, toggle mute when the headset is plugged in.
            guard !isPressed || !isWithinDeviceAttachGracePeriod(inputTimestamp) else { return }
            MediaKeyEvent.post(nxKeyCode: nxKeyCode, isDown: isPressed)
            gestureDiagnosticLogger.info(
                "event=passthrough usage=\(usageText, privacy: .public) value=\(rawValue, privacy: .public)"
            )
            return
        }
        guard let button = HeadsetButton(usagePage: page, usage: usage),
              let channel = channels[button] else { return }

        let mapping = settings.gestureMapping(for: button)
        channel.stateMachine.doubleTapInterval = settings.doubleTapInterval
        channel.stateMachine.longPressDuration = settings.longPressDuration
        channel.stateMachine.maxTapCount = mapping.maxTapCount
        channel.stateMachine.recognizesLongPress = mapping.longPress.enabled
        let isPressed = rawValue != 0
        let isReleaseWithoutPress = !isPressed
            && !channel.lastReportWasPress
            && !isWithinDeviceAttachGracePeriod(inputTimestamp)
        channel.lastReportWasPress = isPressed

        lastInputButton = button
        isHeadsetButtonPressed = isPressed
        currentInputSignalText = isPressed
            ? button.signalText
            : "No key pressed"
        lastRawInputValue = rawValue
        if isReleaseWithoutPress {
            handleReleaseWithoutPress(on: channel, rawValue: rawValue, inputTimestamp: inputTimestamp)
            return
        }

        if !settings.longPressRecognitionEnabled {
            handleTapOnlySignal(
                on: channel,
                isPressed: isPressed,
                rawValue: rawValue,
                inputTimestamp: inputTimestamp
            )
            return
        }

        if isPressed {
            if channel.stateMachine.isDown {
                guard channel.stateMachine.recoverStuckPress(at: inputTimestamp) else {
                    recordInputEvent(
                        kind: .press,
                        title: "Repeated press",
                        detail: String(format: "%@ · raw value %d", button.signalText, rawValue)
                    )
                    gestureDiagnosticLogger.info("event=repeated_down action=ignored")
                    return
                }
                channel.cancelPressTimers()
                recordStuckPressRecovery(on: channel, recoveredAt: inputTimestamp, newPressWasPreserved: true)
            }
            pressSequence += 1
            channel.activePressDiagnostic = ActivePressDiagnostic(
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
                    format: "%@ · sample #%d · input delivery %.1f ms",
                    button.shortTitle,
                    pressSequence,
                    deliveryMilliseconds
                )
            )
            gestureDiagnosticLogger.info(
                "sample=\(self.pressSequence, privacy: .public) event=down button=\(button.rawValue, privacy: .public) input_delivery_ms=\(deliveryText, privacy: .public) threshold_ms=\(thresholdText, privacy: .public)"
            )

            let tapNumber = channel.stateMachine.nextTapNumber(at: inputTimestamp)
            channel.tapSequenceWorkItem?.cancel()
            channel.tapSequenceWorkItem = nil
            pressBeganAt = timestamp
            switch tapNumber {
            case 2:
                gesturePreviewText = "Second tap pressed"
            case 3:
                gesturePreviewText = "Third tap pressed"
            default:
                gesturePreviewText = "Holding…"
            }
            emit(channel.stateMachine.buttonDown(at: inputTimestamp), on: channel)
            if channel.stateMachine.recognizesLongPress {
                longPressDurationOverlay.begin(
                    at: timestamp,
                    threshold: settings.longPressDuration
                )
                scheduleLongPress(on: channel, after: settings.longPressDuration)
            }
        } else {
            longPressDurationOverlay.end()
            pressBeganAt = nil
            channel.cancelPressTimers()
            let recoveredReleaseOnlyTap = channel.stateMachine.isAwaitingReleaseOnlyTap
            let gestures = channel.stateMachine.buttonUp(at: inputTimestamp)
            if recoveredReleaseOnlyTap {
                recordRecoveredReleaseOnlyTap()
            } else {
                recordReleaseDiagnostic(
                    on: channel,
                    inputUpAt: inputTimestamp,
                    callbackUpAt: timestamp,
                    releaseGestures: gestures
                )
            }
            emit(gestures, on: channel)
            if channel.stateMachine.hasPendingTapSequence {
                gesturePreviewText = channel.stateMachine.pendingTapCount == 1
                    ? "Waiting for second tap"
                    : "Waiting for third tap"
                scheduleTapSequenceResolution(on: channel, after: settings.doubleTapInterval)
            } else if gestures.isEmpty, gesturePreviewText != "Long press recognized" {
                gesturePreviewText = "Released"
            }
        }
    }

    private func handleTapOnlySignal(
        on channel: ButtonChannel,
        isPressed: Bool,
        rawValue: Int,
        inputTimestamp: TimeInterval
    ) {
        channel.cancelPressTimers()
        longPressDurationOverlay.end()
        pressBeganAt = nil
        channel.activePressDiagnostic = nil
        isHeadsetButtonPressed = false

        guard isPressed else {
            if channel.stateMachine.isDown || channel.stateMachine.isAwaitingReleaseOnlyTap {
                channel.stateMachine.reset()
            }
            currentInputSignalText = "No key pressed"
            recordInputEvent(
                kind: .release,
                title: "Released",
                detail: "\(channel.button.shortTitle) · tap-only mode · release not required"
            )
            return
        }

        guard registerTap(on: channel, at: inputTimestamp) else {
            gestureDiagnosticLogger.info("event=tap_only_down action=debounced")
            return
        }
        currentInputSignalText = "Tap pulse accepted"
        recordInputEvent(
            kind: .press,
            title: "Tap pulse",
            detail: String(format: "%@ · tap-only mode · raw value %d", channel.button.shortTitle, rawValue)
        )
        lastGestureDiagnosticText = "Tap-only mode: the press pulse was accepted without waiting for release."
        gestureDiagnosticLogger.info("event=tap_only_down action=accepted")
    }

    /// The headset sometimes drops the press report of a click and only sends the
    /// release. Count that release as the tap instead of losing the click.
    private func handleReleaseWithoutPress(
        on channel: ButtonChannel,
        rawValue: Int,
        inputTimestamp: TimeInterval
    ) {
        channel.cancelPressTimers()
        longPressDurationOverlay.end()
        pressBeganAt = nil
        channel.activePressDiagnostic = nil
        isHeadsetButtonPressed = false
        currentInputSignalText = "No key pressed"

        guard registerTap(on: channel, at: inputTimestamp) else {
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
    private func registerTap(on channel: ButtonChannel, at inputTimestamp: TimeInterval) -> Bool {
        if let lastTapOnlyActivationAt = channel.lastTapOnlyActivationAt,
           inputTimestamp - lastTapOnlyActivationAt < Self.tapOnlyDebounceInterval {
            return false
        }
        channel.lastTapOnlyActivationAt = inputTimestamp

        channel.tapSequenceWorkItem?.cancel()
        channel.tapSequenceWorkItem = nil
        emit(channel.stateMachine.registerTap(at: inputTimestamp), on: channel)
        if channel.stateMachine.hasPendingTapSequence {
            gesturePreviewText = channel.stateMachine.pendingTapCount == 1
                ? "Waiting for second tap"
                : "Waiting for third tap"
            scheduleTapSequenceResolution(on: channel, after: settings.doubleTapInterval)
        }
        return true
    }

    private func isWithinDeviceAttachGracePeriod(_ inputTimestamp: TimeInterval) -> Bool {
        guard let lastDeviceAddedAt else { return false }
        return inputTimestamp - lastDeviceAddedAt < Self.deviceAttachGracePeriod
    }

    private func scheduleTapSequenceResolution(on channel: ButtonChannel, after delay: TimeInterval) {
        channel.tapSequenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak channel] in
            guard let self, let channel else { return }
            let gestures = channel.stateMachine.tapSequenceThresholdReached(
                at: ProcessInfo.processInfo.systemUptime
            )
            channel.tapSequenceWorkItem = nil
            self.emit(gestures, on: channel)
        }
        channel.tapSequenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleLongPress(on channel: ButtonChannel, after delay: TimeInterval) {
        channel.longPressWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak channel] in
            guard let self, let channel else { return }
            let timestamp = ProcessInfo.processInfo.systemUptime
            channel.longPressWorkItem = nil
            if channel.stateMachine.isDown {
                channel.activePressDiagnostic?.longPressThresholdReached = true
                if let sample = channel.activePressDiagnostic {
                    switch sample.longPressTriggerMode {
                    case .onRelease:
                        self.gesturePreviewText = "Release to confirm long press"
                        self.scheduleStuckPressRecovery(
                            on: channel,
                            for: sample.sequence,
                            after: Self.releaseConfirmationWindow
                        )
                    case .immediately:
                        let gestures = channel.stateMachine.longPressThresholdReached(at: timestamp)
                        channel.activePressDiagnostic?.longPressWasEmittedImmediately = gestures.contains(.longPress)
                        self.emit(gestures, on: channel)
                    }

                    let callbackHoldMilliseconds = (timestamp - sample.callbackDownAt) * 1_000
                    let callbackHoldText = String(format: "%.1f", callbackHoldMilliseconds)
                    gestureDiagnosticLogger.info(
                        "sample=\(sample.sequence, privacy: .public) event=long_press_threshold mode=\(sample.longPressTriggerMode.rawValue, privacy: .public) callback_hold_ms=\(callbackHoldText, privacy: .public)"
                    )
                }
            }
        }
        channel.longPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleStuckPressRecovery(
        on channel: ButtonChannel,
        for sampleSequence: Int,
        after delay: TimeInterval
    ) {
        channel.stuckPressWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak channel] in
            guard let self,
                  let channel,
                  channel.activePressDiagnostic?.sequence == sampleSequence,
                  channel.stateMachine.isDown else {
                return
            }

            let timestamp = ProcessInfo.processInfo.systemUptime
            guard channel.stateMachine.recoverStuckPress(
                at: timestamp,
                acceptingNextReleaseAsTap: true
            ) else { return }

            channel.stuckPressWorkItem = nil
            self.longPressDurationOverlay.end()
            self.pressBeganAt = nil
            self.isHeadsetButtonPressed = false
            self.currentInputSignalText = "No key pressed (recovered)"
            self.lastRawInputValue = 0
            self.gesturePreviewText = "Missing release; input reset"
            self.recordStuckPressRecovery(
                on: channel,
                recoveredAt: timestamp,
                newPressWasPreserved: false
            )
        }
        channel.stuckPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func recordStuckPressRecovery(
        on channel: ButtonChannel,
        recoveredAt: TimeInterval,
        newPressWasPreserved: Bool
    ) {
        guard let sample = channel.activePressDiagnostic else { return }
        channel.activePressDiagnostic = nil

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
        on channel: ButtonChannel,
        inputUpAt: TimeInterval,
        callbackUpAt: TimeInterval,
        releaseGestures: [RecognizedGesture]
    ) {
        guard let sample = channel.activePressDiagnostic else {
            recordInputEvent(kind: .release, title: "Released", detail: "No matching press sample")
            gestureDiagnosticLogger.info("event=up result=unmatched_release")
            return
        }
        channel.activePressDiagnostic = nil

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

    private func emit(_ gestures: [RecognizedGesture], on channel: ButtonChannel) {
        let button = channel.button
        for gesture in gestures {
            gestureDiagnosticLogger.info(
                "event=gesture button=\(button.rawValue, privacy: .public) type=\(String(describing: gesture), privacy: .public)"
            )
            if settings.playGestureSound {
                GestureFeedbackSound.play(for: gesture)
            }
            let action = settings.gestureMapping(for: button).action(for: gesture)
            let output = action.summary
            let name = Self.gestureName(gesture, on: button)
            lastGestureText = "\(name) → \(output)"
            gesturePreviewText = "\(name) recognized"
            mappedOutputPreviewText = output
            recordInputEvent(
                kind: .gesture,
                title: gesture.title,
                detail: "\(button.shortTitle) → \(output)"
            )
            action.perform()
        }
    }

    /// "Double tap" for Play/Pause, which existing users know as the only button,
    /// and "Vol+ double tap" for the volume buttons.
    private static func gestureName(_ gesture: RecognizedGesture, on button: HeadsetButton) -> String {
        guard button != .playPause else { return gesture.title }
        return "\(button.shortTitle) \(gesture.title.lowercased())"
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
        for channel in channels.values {
            channel.stuckPressWorkItem?.cancel()
            channel.stuckPressWorkItem = nil
            channel.activePressDiagnostic = nil
            channel.lastTapOnlyActivationAt = nil
            channel.lastReportWasPress = false
        }
        longPressDurationOverlay.end()
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
