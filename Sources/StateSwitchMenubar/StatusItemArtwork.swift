import AppKit

struct StatusItemArtwork {
    static func makeImage(theme: AppTheme, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let insetRect = rect.insetBy(dx: 1.2, dy: 1.2)
        let outerPath = NSBezierPath(ovalIn: insetRect)
        NSColor.white.withAlphaComponent(0.96).setFill()
        outerPath.fill()

        let innerRect = insetRect.insetBy(dx: size * 0.14, dy: size * 0.14)
        let gradient = NSGradient(colors: [
            NSColor(hex: theme.palette.accentSoftHex) ?? .white,
            NSColor(hex: theme.palette.accentPrimaryHex) ?? .systemOrange,
            NSColor(hex: theme.palette.accentSecondaryHex) ?? .systemTeal,
        ])
        gradient?.draw(in: NSBezierPath(ovalIn: innerRect), angle: -42)

        let ringRect = innerRect.insetBy(dx: 0.8, dy: 0.8)
        let ringPath = NSBezierPath(ovalIn: ringRect)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        ringPath.lineWidth = 1.1
        ringPath.stroke()

        let coreRect = NSRect(
            x: rect.midX - size * 0.13,
            y: rect.midY - size * 0.13,
            width: size * 0.26,
            height: size * 0.26
        )
        let corePath = NSBezierPath(ovalIn: coreRect)
        (NSColor(hex: theme.palette.inkHex) ?? .black).setFill()
        corePath.fill()

        let accentRect = NSRect(
            x: rect.maxX - size * 0.28,
            y: rect.minY + size * 0.02,
            width: size * 0.18,
            height: size * 0.18
        )
        let accentPath = NSBezierPath(ovalIn: accentRect)
        (NSColor(hex: theme.palette.accentPrimaryHex) ?? .systemOrange).setFill()
        accentPath.fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
