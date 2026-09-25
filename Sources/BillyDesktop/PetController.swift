import AppKit
import BillyCore

/// Ein Schritt in Billys Handlungskette.
enum PetAction {
    /// Laufen zu einem Fußpunkt (globale Bildschirmkoordinaten).
    case walk(to: CGPoint, speed: CGFloat = 1, carry: Bool = false, faceLeftOnArrival: Bool? = nil)
    /// Eine Pose für eine feste Dauer abspielen.
    case pose(Animation, duration: TimeInterval)
    /// Sprechblase zeigen (sofort weiter).
    case say(String)
    /// Beliebiger Code (sofort weiter).
    case run(() -> Void)
}

/// Steuert Billy: Position, Animation, Handlungskette und freies Herumstreunen.
@MainActor
final class PetController: NSObject, PetViewDelegate {
    let window = PetWindow.make()
    let view = PetView()
    private(set) var sprites: SpriteLibrary

    /// Fußpunkt in globalen Bildschirmkoordinaten.
    private(set) var position: CGPoint
    private var animation: Animation = .stand
    private var restAnimation: Animation = .stand
    private var animClock: Double = 0
    private var queue: [PetAction] = []
    private var current: PetAction?
    private var currentElapsed: TimeInterval = 0
    private var nextIdleDecision = Date().addingTimeInterval(4)
    private var lastInteraction = Date()
    private var bubbleUntil: Date?
    private var heartUntil: Date?
    private var dragging = false
    private var timer: Timer?
    private var lastTick = Date()

    var onDoubleClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    var autonomous: Bool {
        get { Settings.shared.autonomous }
        set { Settings.shared.autonomous = newValue }
    }

    var isBusy: Bool { current != nil || !queue.isEmpty }

    init(sprites: SpriteLibrary) {
        self.sprites = sprites
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        position = CGPoint(x: screen.maxX - 220, y: screen.minY + 30)
        super.init()
        view.delegate = self
        window.contentView = view
        applySettings()
        window.orderFrontRegardless()
        timer = Timer.scheduledTimer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        say("Wuff! Ich bin Billy. 🐾")
    }

    func applySettings() {
        let scale = Settings.shared.scale
        view.scale = scale
        view.frameSize = sprites.frameSize
        view.groundY = sprites.groundY
        window.setContentSize(PetView.windowSize(frameSize: sprites.frameSize, scale: scale))
        window.applyLevel(alwaysOnTop: Settings.shared.alwaysOnTop)
        updateWindowPosition()
        render()
    }

    func replaceSprites(_ library: SpriteLibrary) {
        sprites = library
        applySettings()
    }

    // MARK: Öffentliche Steuerung

    func enqueue(_ actions: [PetAction]) {
        queue.append(contentsOf: actions)
        lastInteraction = Date()
    }

    /// Bricht alles ab, was Billy gerade tut.
    func interrupt() {
        queue.removeAll()
        current = nil
        view.carriedIcon = nil
        lastInteraction = Date()
    }

    func rest(_ animation: Animation) {
        restAnimation = animation
        lastInteraction = Date()
        nextIdleDecision = Date().addingTimeInterval(.random(in: 10...20))
    }

    func say(_ text: String, seconds: TimeInterval? = nil) {
        view.bubbleText = text
        bubbleUntil = Date().addingTimeInterval(seconds ?? max(2.5, min(8, Double(text.count) / 12)))
        render()
    }

    func heart() {
        heartUntil = Date().addingTimeInterval(1.8)
    }

    var screenFrame: CGRect {
        let screen = NSScreen.screens.first { $0.frame.contains(position) } ?? NSScreen.main
        return screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Fenster-Rechteck von Billy in globalen Koordinaten (für Chat-Positionierung).
    var windowFrame: CGRect { window.frame }

    /// Zufälliger, gut sichtbarer Fußpunkt auf dem aktuellen Bildschirm.
    func randomSpot() -> CGPoint {
        let area = walkableArea()
        return CGPoint(x: .random(in: area.minX...area.maxX), y: .random(in: area.minY...area.maxY))
    }

    func walkableArea() -> CGRect {
        let s = screenFrame
        let half = sprites.frameSize.width * view.scale / 2
        let top = sprites.frameSize.height * view.scale + 20
        return CGRect(x: s.minX + half, y: s.minY + 4, width: max(1, s.width - 2 * half), height: max(1, s.height - top))
    }

    func clampToScreen(_ p: CGPoint) -> CGPoint {
        let a = walkableArea()
        return CGPoint(x: min(max(p.x, a.minX), a.maxX), y: min(max(p.y, a.minY), a.maxY))
    }

    /// Fußpunkt, bei dem der Anker (z. B. Maul) genau auf `target` liegt.
    func feetPoint(placing anchor: String, of animation: Animation, at target: CGPoint, faceLeft: Bool) -> CGPoint {
        guard let frame = sprites.frames(animation).first else { return target }
        let scale = view.scale
        let a = frame.anchor(anchor)
        let dx = (a.x - sprites.frameSize.width / 2) * scale * (faceLeft ? -1 : 1)
        let dy = (sprites.groundY - a.y) * scale
        return CGPoint(x: target.x - dx, y: target.y - dy)
    }

    // MARK: Takt

    @objc private func tick() {
        let now = Date()
        let dt = min(0.1, now.timeIntervalSince(lastTick))
        lastTick = now
        animClock += dt
        view.tick &+= 1

        if !dragging { advance(dt: dt) }
        if let until = bubbleUntil, now > until { view.bubbleText = nil; bubbleUntil = nil }
        view.showHeart = heartUntil.map { now < $0 } ?? false
        updateMousePassthrough()
        render()
    }

    private func advance(dt: TimeInterval) {
        if current == nil, !queue.isEmpty {
            current = queue.removeFirst()
            currentElapsed = 0
        }
        guard let action = current else {
            setAnimation(restAnimation)
            idleBehaviour()
            return
        }
        currentElapsed += dt
        switch action {
        case let .walk(target, speed, carry, faceLeftOnArrival):
            let pxPerSecond = 120 * view.scale * speed
            let dx = target.x - position.x, dy = target.y - position.y
            let dist = hypot(dx, dy)
            setAnimation(carry ? .carry : .walk)
            if abs(dx) > 1 { view.facingLeft = dx < 0 }
            let step = pxPerSecond * dt
            if dist <= step {
                position = target
                if let face = faceLeftOnArrival { view.facingLeft = face }
                finishAction()
            } else {
                position.x += dx / dist * step
                position.y += dy / dist * step
            }
            updateWindowPosition()
        case let .pose(anim, duration):
            setAnimation(anim)
            if currentElapsed >= duration { finishAction() }
        case let .say(text):
            say(text)
            finishAction()
        case let .run(block):
            finishAction()
            block()
        }
    }

    private func finishAction() {
        current = nil
        currentElapsed = 0
    }

    private func setAnimation(_ anim: Animation) {
        if anim != animation {
            animation = anim
            animClock = 0
        }
    }

    /// Freies Verhalten, wenn nichts in der Warteschlange steht.
    private func idleBehaviour() {
        let now = Date()
        if now.timeIntervalSince(lastInteraction) > 180, restAnimation != .sleep {
            restAnimation = .sleep
            return
        }
        guard autonomous, now >= nextIdleDecision, restAnimation != .sleep else { return }
        nextIdleDecision = now.addingTimeInterval(.random(in: 6...16))
        switch Int.random(in: 0..<10) {
        case 0...3:
            restAnimation = .stand
            enqueue([.walk(to: randomSpot())])
            lastInteraction = now.addingTimeInterval(-60)
        case 4...5:
            restAnimation = .sit
        case 6:
            restAnimation = .lie
        case 7:
            enqueue([.pose(.sniff, duration: 2.5)])
        default:
            restAnimation = .stand
        }
    }

    private func render() {
        let frames = sprites.frames(animation)
        guard !frames.isEmpty else { return }
        let index = Int(animClock * animation.fps) % frames.count
        view.spriteFrame = frames[index]
        view.sleeping = animation == .sleep
        if sprites.needsProceduralBob, animation == .walk || animation == .carry {
            view.bob = abs(sin(animClock * 10)) * 4 * view.scale
        } else {
            view.bob = 0
        }
        view.needsDisplay = true
    }

    private func updateWindowPosition() {
        let size = PetView.windowSize(frameSize: sprites.frameSize, scale: view.scale)
        let feet = CGPoint(x: size.width / 2, y: (sprites.frameSize.height - sprites.groundY) * view.scale)
        window.setFrameOrigin(CGPoint(x: round(position.x - feet.x), y: round(position.y - feet.y)))
    }

    /// Klicks gehen nur dort an Billy, wo er wirklich ist – sonst an die Apps darunter.
    private func updateMousePassthrough() {
        if dragging { window.ignoresMouseEvents = false; return }
        let mouse = NSEvent.mouseLocation
        let local = CGPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
        let hit = view.hitsDog(atViewPoint: local) || (view.bubbleRect?.contains(local) ?? false)
        if window.ignoresMouseEvents == hit {
            window.ignoresMouseEvents = !hit
        }
    }

    // MARK: PetViewDelegate

    func petViewClicked(_ view: PetView, clickCount: Int) {
        lastInteraction = Date()
        if clickCount >= 2 {
            onDoubleClick?()
            return
        }
        if restAnimation == .sleep {
            restAnimation = .stand
            say("Hm? Ich bin wach! 🐶")
            return
        }
        guard !isBusy else { return }
        heart()
        enqueue([.pose(.happy, duration: 1.2)])
        say(["Wuff! ❤️", "Kraulen! 🥰", "Nochmal!", "Hihi, das kitzelt!"].randomElement()!)
    }

    func petViewDragged(_ view: PetView, by delta: CGPoint) {
        if !dragging {
            dragging = true
            setAnimation(.happy)
        }
        position = CGPoint(x: position.x + delta.x, y: position.y + delta.y)
        updateWindowPosition()
    }

    func petViewDragEnded(_ view: PetView) {
        dragging = false
        position = clampToScreen(position)
        updateWindowPosition()
        lastInteraction = Date()
        say(["Huch!", "Wo bin ich? 🐾", "Nochmal fliegen!"].randomElement()!)
    }

    func petViewMenu(_ view: PetView) -> NSMenu? {
        menuProvider?()
    }
}
