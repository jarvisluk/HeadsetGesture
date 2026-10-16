import AppKit
import SwiftUI

@MainActor
final class LongPressDurationOverlayController {
    private static let windowSize = CGSize(width: 176, height: 84)
    private static let updateInterval: TimeInterval = 1.0 / 30.0

    private let settings: SettingsStore
    private var panel: NSPanel?
    private var timer: Timer?
    private var pressStartedAt: TimeInterval?
    private var longPressThreshold: TimeInterval = 0
    private var focusedInputLocation: FocusedInputLocation?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func begin(at timestamp: TimeInterval, threshold: TimeInterval) {
        end()
        pressStartedAt = timestamp
        longPressThreshold = threshold
        focusedInputLocation = settings.longPressDisplayPosition == .focusedInput
            ? FocusedInputLocator.current()
            : nil
        updatePresentation()

        let timer = Timer(timeInterval: Self.updateInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePresentation()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func end() {
        timer?.invalidate()
        timer = nil
        pressStartedAt = nil
        focusedInputLocation = nil
        panel?.orderOut(nil)
    }

    private func updatePresentation() {
        guard settings.showLongPressDuration,
              let pressStartedAt else {
            panel?.orderOut(nil)
            return
        }

        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - pressStartedAt)
        let panel = panel ?? makePanel()
        let content = LongPressDurationOverlayView(
            elapsed: elapsed,
            threshold: longPressThreshold
        )
        if let hostingView = panel.contentView as? NSHostingView<LongPressDurationOverlayView> {
            hostingView.rootView = content
        } else {
            panel.contentView = NSHostingView(rootView: content)
        }

        position(panel)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]
        panel.contentView = NSHostingView(
            rootView: LongPressDurationOverlayView(elapsed: 0, threshold: longPressThreshold)
        )
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        if settings.longPressDisplayPosition == .focusedInput,
           let focusedInputLocation {
            let origin = FocusedInputOverlayPlacement.windowOrigin(
                nextTo: focusedInputLocation.frame,
                windowSize: Self.windowSize,
                visibleFrame: focusedInputLocation.screen.visibleFrame
            )
            panel.setFrameOrigin(origin)
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        guard let screen else { return }

        let origin = settings.longPressDisplayPosition.windowOrigin(
            windowSize: Self.windowSize,
            visibleFrame: screen.visibleFrame
        )
        panel.setFrameOrigin(origin)
    }
}

private struct LongPressDurationOverlayView: View {
    let elapsed: TimeInterval
    let threshold: TimeInterval

    private var thresholdReached: Bool {
        elapsed >= threshold
    }

    var body: some View {
        VStack(spacing: 5) {
            Label(
                thresholdReached ? "Long press" : "Holding",
                systemImage: thresholdReached ? "checkmark.circle.fill" : "hand.tap.fill"
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(thresholdReached ? Color.green : Color.secondary)

            Text(elapsed, format: .number.precision(.fractionLength(2)))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .overlay(alignment: .trailing) {
                    Text("s")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .offset(x: 14, y: 5)
                }
        }
        .frame(width: 176, height: 84)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold duration")
        .accessibilityValue("\(elapsed, specifier: "%.2f") seconds")
    }
}
