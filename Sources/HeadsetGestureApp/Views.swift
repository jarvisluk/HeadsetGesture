import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: HeadsetController
    @State private var selectedTab: MainTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(
                settings: settings,
                controller: controller,
                enabled: enabledBinding
            )
            .tabItem {
                Label("Dashboard", systemImage: "gauge")
            }
            .tag(MainTab.dashboard)

            CustomizationView(settings: settings)
                .tabItem {
                    Label("Customization", systemImage: "slider.horizontal.3")
                }
                .tag(MainTab.customization)
        }
        .frame(width: 620, height: 780)
        .onAppear {
            controller.refreshPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshPermissionsAndReconnectIfNeeded()
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.enabled },
            set: { newValue in
                settings.enabled = newValue
                controller.applyEnabled(newValue)
            }
        )
    }
}

private enum MainTab: Hashable {
    case dashboard
    case customization
}

private struct DashboardView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: HeadsetController
    @Binding var enabled: Bool

    var body: some View {
        Form {
            Section("Status") {
                Toggle("Enable Headset interception", isOn: $enabled)
                LabeledContent("Device", value: controller.statusText)
                LabeledContent("Last action", value: controller.lastGestureText)
            }

            Section("Permissions") {
                LabeledContent(
                    "Input Monitoring",
                    value: controller.inputMonitoringStatusText
                )
                LabeledContent(
                    "Accessibility",
                    value: controller.accessibilityGranted ? "Granted" : "Not granted"
                )

                if !controller.inputMonitoringGranted || !controller.accessibilityGranted {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accessibility permission is required to send custom keys and also grants event listening. Input Monitoring is only needed when Accessibility is not granted.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if !controller.inputMonitoringGranted {
                            Button("Request Input Monitoring Permission") {
                                controller.requestInputMonitoringPermission()
                            }
                        }
                        if !controller.accessibilityGranted {
                            Button("Request Accessibility Permission") {
                                controller.requestAccessibilityPermission()
                            }
                        }
                        Button("Reconnect After Granting Access") {
                            controller.refreshPermissionsAndReconnectIfNeeded()
                        }
                        Button("Restart App After Granting Access") {
                            controller.restartApp()
                        }
                    }
                }
            }

            Section("Live Input Monitor") {
                LiveInputPreviewView(settings: settings, controller: controller)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CustomizationView: View {
    @ObservedObject var settings: SettingsStore
    @State private var selectedButton: HeadsetButton = .playPause

    var body: some View {
        Form {
            Section("App") {
                LabeledContent("Saving", value: settings.saveStatusText)
                    .foregroundStyle(settings.saveErrorText == nil ? Color.secondary : Color.red)

                Toggle("Show icon in Dock", isOn: $settings.showDockIcon)
                Text("When the Dock icon is hidden, open the dashboard from the menu bar icon.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Gesture Detection") {
                Toggle("Enable long-press recognition", isOn: $settings.longPressRecognitionEnabled)

                Text(settings.longPressRecognitionEnabled
                    ? "Long-press recognition is active. Press and release timing is used to distinguish taps from holds."
                    : "Tap-only mode is active. Recommended for headsets that may miss release events: taps do not wait for release, and long-press actions and display are disabled."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                HStack {
                    Text("Double-tap interval")
                    Slider(value: $settings.doubleTapInterval, in: 0.20...0.60, step: 0.05)
                    Text("\(settings.doubleTapInterval, specifier: "%.2f") sec")
                        .monospacedDigit()
                        .frame(width: 62, alignment: .trailing)
                }
                HStack {
                    Text("Long-press duration")
                    Slider(value: $settings.longPressDuration, in: 0.35...1.50, step: 0.05)
                    Text("\(settings.longPressDuration, specifier: "%.2f") sec")
                        .monospacedDigit()
                        .frame(width: 62, alignment: .trailing)
                }
                .disabled(!settings.longPressRecognitionEnabled)

                Picker("Long-press trigger", selection: $settings.longPressTriggerMode) {
                    ForEach(LongPressTriggerMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.longPressRecognitionEnabled)

                Text(settings.longPressTriggerMode.guidance)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .opacity(settings.longPressRecognitionEnabled ? 1 : 0.55)

                Toggle("Play sound when a gesture is recognized", isOn: $settings.playGestureSound)
                ForEach(RecognizedGesture.allCases, id: \.self) { gesture in
                    GestureSoundPicker(gesture: gesture, sound: soundBinding(for: gesture))
                }
                .disabled(!settings.playGestureSound)
                Text("Choosing a sound plays it. Use the speaker button to hear it again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Button") {
                Picker("Button", selection: $selectedButton) {
                    ForEach(HeadsetButton.allCases) { button in
                        Text(button.title).tag(button)
                    }
                }
                .pickerStyle(.segmented)

                Text("USB-C headsets and Apple-standard wired remotes report separate volume buttons. On most other wired headsets every button reports Play/Pause, so only the Play/Pause mappings apply.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Single Tap") {
                ActionEditor(action: actionBinding(for: .singleTap))
                Text(selectedMapping.maxTapCount == 1
                    ? "Double and triple tap are off, so a single tap runs immediately."
                    : "A single tap runs after the double-tap interval expires."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Double Tap") {
                ActionEditor(action: actionBinding(for: .doubleTap))
                Text(selectedMapping.maxTapCount == 3
                    ? "A double tap runs after the tap interval expires so a third tap can still be detected."
                    : "Triple tap is off, so a double tap runs on the second tap."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Triple Tap") {
                ActionEditor(action: actionBinding(for: .tripleTap))
                Text("Off by default. The third tap runs immediately when enabled.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Long Press") {
                ActionEditor(action: actionBinding(for: .longPress))
                Text("When this action is off, holding the button counts as a tap.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.longPressRecognitionEnabled)

            Section("Long-Press Display") {
                Toggle("Show hold duration on screen", isOn: $settings.showLongPressDuration)

                Picker("Position", selection: $settings.longPressDisplayPosition) {
                    ForEach(LongPressDisplayPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
                .disabled(!settings.showLongPressDuration)

                Text("The timer appears while the headset button is held and changes state when the long-press threshold is reached.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if settings.longPressDisplayPosition == .focusedInput {
                    Text("Locating a focused input in another app requires Accessibility permission. The timer falls back to the bottom of the screen when no input can be located.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!settings.longPressRecognitionEnabled)
        }
        .formStyle(.grouped)
    }

    private var selectedMapping: ButtonGestureMapping {
        settings.gestureMapping(for: selectedButton)
    }

    private func soundBinding(for gesture: RecognizedGesture) -> Binding<FeedbackSound> {
        Binding(
            get: { settings.gestureSounds.sound(for: gesture) },
            set: { settings.gestureSounds.setSound($0, for: gesture) }
        )
    }

    private func actionBinding(for gesture: RecognizedGesture) -> Binding<KeyAction> {
        let button = selectedButton
        return Binding(
            get: { settings.gestureMapping(for: button).action(for: gesture) },
            set: { settings.setAction($0, for: gesture, on: button) }
        )
    }
}

private struct GestureSoundPicker: View {
    let gesture: RecognizedGesture
    @Binding var sound: FeedbackSound

    var body: some View {
        HStack {
            Picker(gesture.title, selection: $sound) {
                ForEach(FeedbackSound.allCases) { sound in
                    Text(sound.title).tag(sound)
                }
            }
            .onChange(of: sound) { newSound in
                GestureFeedbackSound.play(newSound)
            }

            Button {
                GestureFeedbackSound.play(sound)
            } label: {
                Image(systemName: "speaker.wave.2")
            }
            .buttonStyle(.borderless)
            .help("Preview \(sound.title)")
            .accessibilityLabel("Preview \(gesture.title) sound")
        }
    }
}

private struct ActionEditor: View {
    @Binding var action: KeyAction

    var body: some View {
        Toggle("Perform custom action", isOn: $action.enabled)

        Picker("Action type", selection: $action.kind) {
            ForEach(ActionKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .disabled(!action.enabled)

        if action.enabled {
            switch action.kind {
            case .keyboard:
                keyboardEditor
            case .rawKeyCode:
                rawKeyCodeEditor
            case .media:
                Picker("Media key", selection: $action.mediaKey) {
                    ForEach(MediaKeyChoice.allCases) { key in
                        Text(key.title).tag(key)
                    }
                }
            case .shortcut:
                TextField("Shortcut name", text: $action.shortcutName)
                Text("The name must exactly match a shortcut in the Shortcuts app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .command:
                TextField("Example: open -a Notes", text: $action.shellCommand)
                Text("Commands run through /bin/zsh -lc. Only enter commands you trust.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        LabeledContent("Result", value: action.summary)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var keyboardEditor: some View {
        Picker("Key", selection: $action.key) {
            ForEach(KeyChoice.allCases) { key in
                Text(key.title).tag(key)
            }
        }
        modifierEditor
    }

    @ViewBuilder
    private var rawKeyCodeEditor: some View {
        HStack {
            Stepper("Raw key code", value: $action.rawKeyCode, in: 0...127)
            Text("\(action.rawKeyCode)")
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
        modifierEditor
        Text("Experimental: some key codes have no system meaning and are only visible to software that listens for raw CGEvents.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var modifierEditor: some View {
        HStack(spacing: 16) {
            Toggle("⌃ Control", isOn: $action.control)
            Toggle("⌥ Option", isOn: $action.option)
            Toggle("⇧ Shift", isOn: $action.shift)
            Toggle("⌘ Command", isOn: $action.command)
        }
        .toggleStyle(.checkbox)
    }
}

/// The menu bar panel (`.menuBarExtraStyle(.window)`): a status header with the
/// interception switch, the last recognized gesture, the gesture map, and a
/// footer with the Dock toggle, Dashboard and Quit.
struct MenuContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: HeadsetController

    private var state: MenuBarState {
        MenuBarState.resolve(
            enabled: settings.enabled,
            isConnected: controller.isConnected,
            accessibilityGranted: controller.accessibilityGranted,
            inputMonitoringGranted: controller.inputMonitoringGranted
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if state == .permissionMissing {
                permissionCallout
            }
            lastAction
            gestureMap
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { controller.refreshPermissionStatus() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(state.tint.opacity(0.16))
                Image(nsImage: MenuBarIcon.image(for: state))
                    .renderingMode(.template)
                    .foregroundStyle(state.tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.title)
                    .font(.headline)
                Text(controller.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Toggle("Interception", isOn: Binding(
                get: { settings.enabled },
                set: { value in
                    settings.enabled = value
                    controller.applyEnabled(value)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .help(settings.enabled ? "Pause interception" : "Resume interception")
        }
    }

    private var permissionCallout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Grant access to read the headset button", systemImage: "lock.shield")
                .font(.callout)
            HStack(spacing: 6) {
                if !controller.inputMonitoringGranted {
                    Button("Input Monitoring") { controller.requestInputMonitoringPermission() }
                }
                if !controller.accessibilityGranted {
                    Button("Accessibility") { controller.requestAccessibilityPermission() }
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var lastAction: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last action")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(controller.lastGestureText)
                .font(.system(.body, design: .rounded).weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var gestureMap: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gestures")
                .font(.caption)
                .foregroundStyle(.secondary)
            GestureRow(pattern: .taps(1), name: "Single tap", action: settings.singleTapAction.summary)
            GestureRow(pattern: .taps(2), name: "Double tap", action: settings.doubleTapAction.summary)
            GestureRow(pattern: .taps(3), name: "Triple tap", action: settings.tripleTapAction.summary)
            GestureRow(
                pattern: .hold,
                name: "Long press",
                action: settings.longPressRecognitionEnabled
                    ? settings.longPressAction.summary
                    : "Off"
            )
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show Dock icon", isOn: $settings.showDockIcon)
                .toggleStyle(.checkbox)
            HStack {
                Button("Open Dashboard…") {
                    dismiss()
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .controlSize(.regular)
        }
    }
}

private extension MenuBarState {
    var tint: Color {
        switch self {
        case .connected: return .accentColor
        case .waiting: return .secondary
        case .paused: return .secondary
        case .permissionMissing: return .orange
        }
    }
}

/// One line of the gesture map: a dot/dash pattern, the gesture name and the
/// action it is mapped to.
private struct GestureRow: View {
    enum Pattern { case taps(Int), hold }

    let pattern: Pattern
    let name: String
    let action: String

    var body: some View {
        HStack(spacing: 8) {
            patternGlyph
                .frame(width: 26, alignment: .leading)
                .foregroundStyle(Color.accentColor)
            Text(name)
            Spacer(minLength: 8)
            Text(action)
                .foregroundStyle(action == "No action" || action == "Off" ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.callout)
    }

    @ViewBuilder private var patternGlyph: some View {
        switch pattern {
        case .taps(let count):
            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle().frame(width: 5, height: 5)
                }
            }
        case .hold:
            Capsule().frame(width: 19, height: 5)
        }
    }
}
