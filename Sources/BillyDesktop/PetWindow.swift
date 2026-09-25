import AppKit

/// Rahmenloses, transparentes Fenster, in dem Billy lebt. Es wandert mit Billy über den Bildschirm.
final class PetWindow: NSPanel {
    static func make() -> PetWindow {
        let window = PetWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        return window
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func applyLevel(alwaysOnTop: Bool) {
        if alwaysOnTop {
            level = .floating
        } else {
            // Direkt über den Schreibtisch-Symbolen, unter normalen Fenstern.
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }
}

@MainActor
protocol PetViewDelegate: AnyObject {
    func petViewClicked(_ view: PetView, clickCount: Int)
    func petViewDragged(_ view: PetView, by delta: CGPoint)
    func petViewDragEnded(_ view: PetView)
    func petViewMenu(_ view: PetView) -> NSMenu?
}

/// Zeichnet Billy, getragene Dateien, Sprechblase und kleine Effekte.
final class PetView: NSView {
    weak var delegate: PetViewDelegate?

    private(set) var spriteFrame: SpriteFrame?
    private var animation: Animation = .stand
    var frameSize = CGSize(width: 160, height: 120)
    var groundY: CGFloat = 112
    var scale: CGFloat = 1
    var facingLeft = false
    /// Foto-Sets: Atmen, Hüpfen und Wippen werden berechnet statt gezeichnet.
    var proceduralLife = false
    var carriedIcon: NSImage?
    var bubbleText: String?
    var showHeart = false
    var time: TimeInterval = 0

    // Überblendung beim Posenwechsel
    private var fadeFrom: (frame: SpriteFrame, facingLeft: Bool, lift: CGFloat)?
    private var fadeStart: TimeInterval = 0
    private let fadeDuration: TimeInterval = 0.16
    // Datei fällt in den Ordner
    private var droppedIcon: (image: NSImage, center: CGPoint, start: TimeInterval)?
    // Landung nach dem Tragen mit der Maus
    private var bounceStart: TimeInterval = -10

    static let bubbleArea: CGFloat = 96
    static let minWidth: CGFloat = 280

    private var dragOrigin: CGPoint?
    private var didDrag = false

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static func windowSize(frameSize: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: max(frameSize.width * scale, minWidth), height: frameSize.height * scale + bubbleArea)
    }

    func setFrame(_ frame: SpriteFrame, animation: Animation) {
        spriteFrame = frame
        self.animation = animation
    }

    /// Nächsten Bildwechsel weich überblenden.
    func crossfade() {
        guard let frame = spriteFrame else { return }
        fadeFrom = (frame, facingLeft, lift)
        fadeStart = time
    }

    /// Getragene Datei loslassen: sie schrumpft in den Ordner.
    func dropCarriedIcon() {
        guard let icon = carriedIcon, let frame = spriteFrame else { return }
        droppedIcon = (icon, iconRect(for: frame).center, time)
        carriedIcon = nil
    }

    func bounce() {
        bounceStart = time
    }

    /// Sprunghöhe (Foto-Sets hüpfen berechnet, alle landen federnd).
    private var lift: CGFloat {
        var y: CGFloat = 0
        if proceduralLife {
            switch animation {
            case .walk, .carry: y += CGFloat(abs(sin(time * 11))) * 3 * scale
            case .run: y += CGFloat(abs(sin(time * 14))) * 9 * scale
            case .hop, .happy: y += CGFloat(abs(sin(time * 9))) * 12 * scale
            default: break
            }
        }
        let b = time - bounceStart
        if b < 0.45 { y += CGFloat(abs(sin(b * 14)) * (0.45 - b)) * 30 * scale }
        return y
    }

    /// Atmen: leichtes Strecken nach oben (nur Foto-Sets, die Zeichnung atmet selbst).
    private var breathScale: CGFloat {
        guard proceduralLife else { return 1 }
        switch animation {
        case .stand, .sit, .lie: return 1 + CGFloat(0.010 * sin(time * 2 * .pi / 3.2))
        case .sleep: return 1 + CGFloat(0.018 * sin(time * 2 * .pi / 4.2))
        default: return 1
        }
    }

    func dogRect(lift: CGFloat? = nil) -> CGRect {
        let w = frameSize.width * scale, h = frameSize.height * scale
        return CGRect(x: (bounds.width - w) / 2, y: lift ?? self.lift, width: w, height: h)
    }

    var dogRect: CGRect { dogRect() }

    /// Fußpunkt (Mitte, Bodenlinie) in View-Koordinaten.
    var feetPoint: CGPoint {
        CGPoint(x: bounds.width / 2, y: (frameSize.height - groundY) * scale)
    }

    /// Ankerpunkt eines Frames in View-Koordinaten (berücksichtigt Spiegelung).
    func viewPoint(forFramePoint p: CGPoint, facingLeft: Bool? = nil) -> CGPoint {
        let rect = dogRect
        let left = facingLeft ?? self.facingLeft
        let x = left ? rect.maxX - p.x * scale : rect.minX + p.x * scale
        return CGPoint(x: x, y: rect.maxY - p.y * scale)
    }

    func framePoint(forViewPoint p: CGPoint) -> CGPoint {
        let rect = dogRect
        let x = facingLeft ? (rect.maxX - p.x) / scale : (p.x - rect.minX) / scale
        return CGPoint(x: x, y: (rect.maxY - p.y) / scale)
    }

    func hitsDog(atViewPoint p: CGPoint) -> Bool {
        guard dogRect.contains(p), let frame = spriteFrame else { return false }
        return frame.isOpaque(at: framePoint(forViewPoint: p), frameSize: frameSize)
    }

    private func iconRect(for frame: SpriteFrame) -> CGRect {
        let mouth = viewPoint(forFramePoint: frame.anchor("mouth"))
        let size = 30 * scale
        return CGRect(x: mouth.x - size / 2, y: mouth.y - size * 0.75, width: size, height: size)
    }

    private func drawDog(_ frame: SpriteFrame, facingLeft: Bool, lift: CGFloat, alpha: CGFloat) {
        guard let ctx = NSGraphicsContext.current else { return }
        let rect = dogRect(lift: lift)
        ctx.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: rect.midX, yBy: rect.minY)
        t.scaleX(by: facingLeft ? -1 : 1, yBy: breathScale)
        t.translateX(by: -rect.midX, yBy: -rect.minY)
        t.concat()
        frame.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
        ctx.restoreGraphicsState()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let frame = spriteFrame else { return }
        let currentLift = lift

        // Bodenschatten für Foto-Sets, der beim Hüpfen kleiner wird
        if proceduralLife {
            let k = max(0.5, 1 - currentLift / (40 * scale))
            let w = frameSize.width * scale * 0.7 * k
            let shadow = NSBezierPath(ovalIn: CGRect(x: bounds.midX - w / 2, y: feetPoint.y - 5 * scale * k,
                                                     width: w, height: 10 * scale * k))
            NSColor.black.withAlphaComponent(0.12 * k).setFill()
            shadow.fill()
        }

        let fade = fadeFrom.map { _ in min(1, (time - fadeStart) / fadeDuration) } ?? 1
        if let from = fadeFrom, fade < 1 {
            drawDog(from.frame, facingLeft: from.facingLeft, lift: from.lift, alpha: 1 - CGFloat(fade))
            drawDog(frame, facingLeft: facingLeft, lift: currentLift, alpha: CGFloat(fade))
        } else {
            fadeFrom = nil
            drawDog(frame, facingLeft: facingLeft, lift: currentLift, alpha: 1)
        }

        if let icon = carriedIcon {
            icon.draw(in: iconRect(for: frame))
        }
        if let drop = droppedIcon {
            let p = CGFloat(min(1, (time - drop.start) / 0.35))
            let size = 30 * scale * (1 - p * 0.8)
            let rect = CGRect(x: drop.center.x - size / 2, y: drop.center.y - size / 2 - p * 10 * scale, width: size, height: size)
            drawIcon(drop.image, in: rect, alpha: 1 - p)
            if p >= 1 { droppedIcon = nil }
        }

        let head = viewPoint(forFramePoint: frame.anchor("head"))
        if animation == .sleep {
            let phase = Int(time * 1.5) % 3
            for i in 0...phase {
                let s = CGFloat(10 + i * 4) * scale
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: s, weight: .bold),
                    .foregroundColor: NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.75, alpha: 0.85),
                ]
                let dx = (facingLeft ? -1 : 1) * CGFloat(8 + i * 10) * scale
                ("z" as NSString).draw(at: CGPoint(x: head.x + dx, y: head.y + CGFloat(i * 12) * scale), withAttributes: attrs)
            }
        }
        if showHeart {
            let s = 20 * scale
            let y = head.y + 8 * scale + CGFloat((time * 30).truncatingRemainder(dividingBy: 20)) * 0.6
            ("❤️" as NSString).draw(at: CGPoint(x: head.x - s / 2, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: s)])
        }
        if let text = bubbleText {
            drawBubble(text, anchor: head)
        }
    }

    private func drawIcon(_ image: NSImage, in rect: CGRect, alpha: CGFloat) {
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
    }

    var bubbleRect: CGRect? {
        guard let text = bubbleText else { return nil }
        return layoutBubble(text, anchor: viewPoint(forFramePoint: spriteFrame?.anchor("head") ?? .zero)).box
    }

    private func bubbleAttributes() -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        return [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
            .paragraphStyle: style,
        ]
    }

    private func layoutBubble(_ text: String, anchor: CGPoint) -> (box: CGRect, textRect: CGRect) {
        let maxWidth = bounds.width - 24
        let attrs = bubbleAttributes()
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth - 20, height: PetView.bubbleArea - 26),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)
        let w = min(maxWidth, ceil(measured.width) + 22)
        let h = min(PetView.bubbleArea - 14, ceil(measured.height) + 14)
        var x = anchor.x - w / 2
        x = max(6, min(bounds.width - w - 6, x))
        let y = max(dogRect.maxY - 18 * scale, anchor.y + 12)
        let clampedY = min(y, bounds.height - h - 2)
        let box = CGRect(x: x, y: clampedY, width: w, height: h)
        return (box, box.insetBy(dx: 10, dy: 7))
    }

    private func drawBubble(_ text: String, anchor: CGPoint) {
        let (box, textRect) = layoutBubble(text, anchor: anchor)
        let path = NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12)
        let tipX = max(box.minX + 14, min(box.maxX - 14, anchor.x))
        path.move(to: CGPoint(x: tipX - 7, y: box.minY + 1))
        path.line(to: CGPoint(x: tipX, y: box.minY - 8))
        path.line(to: CGPoint(x: tipX + 7, y: box.minY + 1))
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = CGSize(width: 0, height: -2)
        shadow.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedWhite: 0.2, alpha: 0.25).setStroke()
        path.lineWidth = 1
        path.stroke()
        (text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                 attributes: bubbleAttributes(), context: nil)
    }

    // MARK: Maus

    override func mouseDown(with event: NSEvent) {
        dragOrigin = NSEvent.mouseLocation
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let now = NSEvent.mouseLocation
        let delta = CGPoint(x: now.x - origin.x, y: now.y - origin.y)
        if !didDrag, hypot(delta.x, delta.y) < 3 { return }
        didDrag = true
        dragOrigin = now
        delegate?.petViewDragged(self, by: delta)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragOrigin = nil }
        if didDrag {
            delegate?.petViewDragEnded(self)
        } else {
            delegate?.petViewClicked(self, clickCount: event.clickCount)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = delegate?.petViewMenu(self) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
