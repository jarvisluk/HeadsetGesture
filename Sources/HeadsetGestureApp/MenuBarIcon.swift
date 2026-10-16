import AppKit

/// What the menu bar item is telling the user, in priority order.
enum MenuBarState: Equatable {
    case permissionMissing
    case paused
    case connected
    case waiting

    static func resolve(
        enabled: Bool,
        isConnected: Bool,
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool
    ) -> MenuBarState {
        if !accessibilityGranted || !inputMonitoringGranted { return .permissionMissing }
        if !enabled { return .paused }
        return isConnected ? .connected : .waiting
    }

    var title: String {
        switch self {
        case .permissionMissing: return "Permission needed"
        case .paused: return "Paused"
        case .connected: return "Listening"
        case .waiting: return "Waiting for headset"
        }
    }
}

/// Monochrome 18 pt template images for the menu bar item.
///
/// Every state shares the same earbud silhouette (the app icon's subject);
/// connected fills it and adds tap marks, the other states outline it and
/// carry a small badge in the lower-right corner.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)
    private static var cache: [MenuBarState: NSImage] = [:]

    static func image(for state: MenuBarState) -> NSImage {
        if let cached = cache[state] { return cached }
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(state, in: ctx)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Headset Gesture – \(state.title)"
        cache[state] = image
        return image
    }

    /// Earbud in an 18 pt, top-left-origin box, leaning right like the app icon.
    private static func earbud() -> CGPath {
        var t = CGAffineTransform(translationX: 8, y: 9)
            .rotated(by: .pi / 14)
            .translatedBy(x: -8, y: -9)
        let head = CGPath(ellipseIn: CGRect(x: 1.6, y: 1.4, width: 8.2, height: 7.2), transform: &t)
        let stem = CGPath(
            roundedRect: CGRect(x: 6.6, y: 4.4, width: 3.2, height: 12.2),
            cornerWidth: 1.6, cornerHeight: 1.6, transform: &t
        )
        return head.union(stem)
    }

    private static func draw(_ state: MenuBarState, in ctx: CGContext) {
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.black.cgColor)
        let bud = earbud()

        switch state {
        case .connected:
            ctx.addPath(bud)
            ctx.fillPath()
            // Knock the speaker grille out so the solid shape still reads as an earbud.
            ctx.setBlendMode(.clear)
            var t = CGAffineTransform(translationX: 8, y: 9).rotated(by: .pi / 14).translatedBy(x: -8, y: -9)
            ctx.addPath(CGPath(
                roundedRect: CGRect(x: 2.9, y: 3.8, width: 3.2, height: 1.8),
                cornerWidth: 0.9, cornerHeight: 0.9, transform: &t
            ))
            ctx.fillPath()
            ctx.setBlendMode(.normal)
            // Tap marks off the stem.
            let c = CGPoint(x: 10.3, y: 12.0)
            ctx.setLineWidth(1.4)
            ctx.setLineCap(.round)
            for angle in [-CGFloat.pi / 4.2, 0, CGFloat.pi / 4.2] {
                ctx.move(to: CGPoint(x: c.x + cos(angle) * 2.6, y: c.y + sin(angle) * 2.6))
                ctx.addLine(to: CGPoint(x: c.x + cos(angle) * 5.4, y: c.y + sin(angle) * 5.4))
            }
            ctx.strokePath()

        case .waiting:
            strokeOutline(bud, in: ctx)

        case .paused:
            strokeOutline(bud, in: ctx)
            clearBadgeArea(in: ctx)
            for x in [12.3, 15.3] {
                ctx.addPath(CGPath(
                    roundedRect: CGRect(x: x, y: 10.6, width: 2.0, height: 6.6),
                    cornerWidth: 0.7, cornerHeight: 0.7, transform: nil
                ))
            }
            ctx.fillPath()

        case .permissionMissing:
            strokeOutline(bud, in: ctx)
            clearBadgeArea(in: ctx)
            ctx.addEllipse(in: badgeRect)
            ctx.fillPath()
            ctx.setBlendMode(.clear)
            ctx.addPath(CGPath(
                roundedRect: CGRect(x: badgeRect.midX - 0.75, y: badgeRect.minY + 1.4, width: 1.5, height: 3.4),
                cornerWidth: 0.6, cornerHeight: 0.6, transform: nil
            ))
            ctx.addEllipse(in: CGRect(x: badgeRect.midX - 0.8, y: badgeRect.maxY - 2.6, width: 1.6, height: 1.6))
            ctx.fillPath()
            ctx.setBlendMode(.normal)
        }
    }

    private static let badgeRect = CGRect(x: 10.4, y: 10.4, width: 7.4, height: 7.4)

    private static func strokeOutline(_ path: CGPath, in ctx: CGContext) {
        ctx.addPath(path)
        ctx.setLineWidth(1.3)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    /// Clears a gap around the badge so it doesn't merge with the outline.
    private static func clearBadgeArea(in ctx: CGContext) {
        ctx.setBlendMode(.clear)
        ctx.addEllipse(in: badgeRect.insetBy(dx: -1.4, dy: -1.4))
        ctx.fillPath()
        ctx.setBlendMode(.normal)
    }
}

