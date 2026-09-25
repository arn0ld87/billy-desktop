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

    var spriteFrame: SpriteFrame?
    var frameSize = CGSize(width: 160, height: 120)
    var groundY: CGFloat = 112
    var scale: CGFloat = 1
    var facingLeft = false
    var bob: CGFloat = 0
    var carriedIcon: NSImage?
    var bubbleText: String?
    var showHeart = false
    var sleeping = false
    var tick: Int = 0

    static let bubbleArea: CGFloat = 96
    static let minWidth: CGFloat = 280

    private var dragOrigin: CGPoint?
    private var didDrag = false

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static func windowSize(frameSize: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: max(frameSize.width * scale, minWidth), height: frameSize.height * scale + bubbleArea)
    }

    var dogRect: CGRect {
        let w = frameSize.width * scale, h = frameSize.height * scale
        return CGRect(x: (bounds.width - w) / 2, y: bob, width: w, height: h)
    }

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

    override func draw(_ dirtyRect: NSRect) {
        guard let frame = spriteFrame, let ctx = NSGraphicsContext.current else { return }
        let rect = dogRect

        ctx.saveGraphicsState()
        if facingLeft {
            let t = NSAffineTransform()
            t.translateX(by: rect.midX, yBy: 0)
            t.scaleX(by: -1, yBy: 1)
            t.translateX(by: -rect.midX, yBy: 0)
            t.concat()
        }
        frame.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        ctx.restoreGraphicsState()

        if let icon = carriedIcon {
            let mouth = viewPoint(forFramePoint: frame.anchor("mouth"))
            let size = 30 * scale
            icon.draw(in: CGRect(x: mouth.x - size / 2, y: mouth.y - size * 0.75, width: size, height: size))
        }

        let head = viewPoint(forFramePoint: frame.anchor("head"))
        if sleeping {
            let phase = (tick / 12) % 3
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
            let y = head.y + 8 * scale + CGFloat(tick % 20) * 0.6
            ("❤️" as NSString).draw(at: CGPoint(x: head.x - s / 2, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: s)])
        }
        if let text = bubbleText {
            drawBubble(text, anchor: head)
        }
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
