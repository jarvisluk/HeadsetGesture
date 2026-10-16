import CoreGraphics
import Foundation

enum LongPressDisplayPosition: String, CaseIterable, Identifiable {
    case focusedInput
    case topLeft
    case top
    case topRight
    case center
    case bottomLeft
    case bottom
    case bottomRight

    var id: Self { self }

    var title: String {
        switch self {
        case .focusedInput: "Beside Focused Input"
        case .topLeft: "Top Left"
        case .top: "Top"
        case .topRight: "Top Right"
        case .center: "Center"
        case .bottomLeft: "Bottom Left"
        case .bottom: "Bottom"
        case .bottomRight: "Bottom Right"
        }
    }

    func windowOrigin(
        windowSize: CGSize,
        visibleFrame: CGRect,
        inset: CGFloat = 28
    ) -> CGPoint {
        let left = visibleFrame.minX + inset
        let centerX = visibleFrame.midX - windowSize.width / 2
        let right = visibleFrame.maxX - windowSize.width - inset
        let bottom = visibleFrame.minY + inset
        let centerY = visibleFrame.midY - windowSize.height / 2
        let top = visibleFrame.maxY - windowSize.height - inset

        switch self {
        case .focusedInput, .bottom:
            return CGPoint(x: centerX, y: bottom)
        case .topLeft:
            return CGPoint(x: left, y: top)
        case .top:
            return CGPoint(x: centerX, y: top)
        case .topRight:
            return CGPoint(x: right, y: top)
        case .center:
            return CGPoint(x: centerX, y: centerY)
        case .bottomLeft:
            return CGPoint(x: left, y: bottom)
        case .bottomRight:
            return CGPoint(x: right, y: bottom)
        }
    }
}

enum FocusedInputOverlayPlacement {
    static func windowOrigin(
        nextTo inputFrame: CGRect,
        windowSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 12,
        inset: CGFloat = 12
    ) -> CGPoint {
        let minimumX = visibleFrame.minX + inset
        let maximumX = visibleFrame.maxX - windowSize.width - inset
        let minimumY = visibleFrame.minY + inset
        let maximumY = visibleFrame.maxY - windowSize.height - inset
        let rightX = inputFrame.maxX + gap
        let leftX = inputFrame.minX - gap - windowSize.width

        let x: CGFloat
        if rightX <= maximumX {
            x = max(minimumX, rightX)
        } else if leftX >= minimumX {
            x = min(maximumX, leftX)
        } else {
            x = min(maximumX, max(minimumX, inputFrame.midX - windowSize.width / 2))
        }

        let centeredY = inputFrame.midY - windowSize.height / 2
        let y = min(maximumY, max(minimumY, centeredY))
        return CGPoint(x: x, y: y)
    }
}
