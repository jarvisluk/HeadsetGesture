import Foundation
import SwiftUI

struct LiveInputEvent: Identifiable {
    enum Kind {
        case press
        case release
        case gesture
    }

    let id = UUID()
    let sequence: Int
    let kind: Kind
    let title: String
    let detail: String
    let occurredAt: Date
}

struct LiveInputPreviewView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: HeadsetController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            signalFlow
            rawSignalDetails
            longPressProgress
            diagnosticSummary
            eventHistory

            HStack(alignment: .firstTextBaseline) {
                Label(
                    "Volume buttons report 0xE9 and 0xEA only on USB-C headsets and Apple-standard remotes; elsewhere every button reports 0xCD.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Button("Clear") {
                    controller.clearInputPreview()
                }
                .disabled(controller.inputEvents.isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    private var diagnosticSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Timing diagnostics", systemImage: "waveform.path.ecg")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(controller.gestureDiagnosticSummaryText)
                .font(.caption.monospacedDigit())
            Text(controller.lastGestureDiagnosticText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    }

    private var signalFlow: some View {
        HStack(spacing: 8) {
            PreviewNode(
                title: "Headset Input",
                value: controller.currentInputSignalText,
                status: controller.isHeadsetButtonPressed ? "Pressed" : "Released",
                systemImage: controller.isHeadsetButtonPressed
                    ? "headphones.circle.fill"
                    : "headphones.circle",
                tint: controller.isHeadsetButtonPressed ? .blue : .secondary
            )

            flowArrow

            PreviewNode(
                title: "Gesture Detector",
                value: controller.gesturePreviewText,
                status: detectorStatus,
                systemImage: "hand.tap",
                tint: detectorTint
            )

            flowArrow

            PreviewNode(
                title: "Mapped Output",
                value: controller.mappedOutputPreviewText,
                status: outputStatus,
                systemImage: "keyboard",
                tint: controller.mappedOutputPreviewText == "No output yet" ? .secondary : .green
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live headset input flow")
    }

    private var flowArrow: some View {
        Image(systemName: "arrow.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private var rawSignalDetails: some View {
        HStack(spacing: 6) {
            Text("HID")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Usage Page 0x0C")
            Text("•")
                .foregroundStyle(.tertiary)
            Text(String(format: "Usage 0x%04X", controller.lastInputButton.usage))
            Text("•")
                .foregroundStyle(.tertiary)
            Text("Value \(controller.lastRawInputValue)")
            Spacer()
            Text("\(controller.inputEvents.count) recent events")
                .foregroundStyle(.secondary)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private var longPressProgress: some View {
        if let pressBeganAt = controller.pressBeganAt, controller.isHeadsetButtonPressed {
            TimelineView(.periodic(from: .now, by: 0.05)) { _ in
                let elapsed = ProcessInfo.processInfo.systemUptime - pressBeganAt
                let progress = min(max(elapsed / settings.longPressDuration, 0), 1)

                HStack(spacing: 10) {
                    Text("Long press")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress)
                    Text("\(min(elapsed, settings.longPressDuration), specifier: "%.2f") / \(settings.longPressDuration, specifier: "%.2f") sec")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)
                }
            }
        }
    }

    private var eventHistory: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent activity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if controller.inputEvents.isEmpty {
                Text("Press a headset button to preview its signal here.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(controller.inputEvents.prefix(5)) { event in
                    HStack(spacing: 8) {
                        Image(systemName: eventIcon(for: event.kind))
                            .foregroundStyle(eventTint(for: event.kind))
                            .frame(width: 16)
                        Text("#\(event.sequence)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                        Text(event.title)
                            .fontWeight(.medium)
                            .frame(width: 76, alignment: .leading)
                        Text(event.detail)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(event.occurredAt, style: .time)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var detectorStatus: String {
        controller.isHeadsetButtonPressed ? "Listening live" : "Monitoring"
    }

    private var detectorTint: Color {
        controller.isHeadsetButtonPressed ? .orange : .secondary
    }

    private var outputStatus: String {
        controller.mappedOutputPreviewText == "No output yet" ? "Waiting" : "Last sent"
    }

    private func eventIcon(for kind: LiveInputEvent.Kind) -> String {
        switch kind {
        case .press: return "arrow.down.circle.fill"
        case .release: return "arrow.up.circle"
        case .gesture: return "sparkles"
        }
    }

    private func eventTint(for kind: LiveInputEvent.Kind) -> Color {
        switch kind {
        case .press: return .blue
        case .release: return .secondary
        case .gesture: return .green
        }
    }
}

private struct PreviewNode: View {
    let title: String
    let value: String
    let status: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)

            Text(status)
                .font(.caption2)
                .foregroundStyle(tint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
