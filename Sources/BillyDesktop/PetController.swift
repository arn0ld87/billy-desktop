import AppKit
import BillyCore

/// Ein Schritt in Billys Handlungskette.
enum PetAction {
    /// Laufen zu einem Fußpunkt (globale Bildschirmkoordinaten). Ab Tempo 2.2 galoppiert Billy.
    case walk(to: CGPoint, speed: CGFloat = 1, carry: Bool = false, faceLeftOnArrival: Bool? = nil)
    /// Eine Schleifen-Pose für eine feste Dauer abspielen.
    case pose(Animation, duration: TimeInterval)
    /// Eine Einmal-Animation genau einmal abspielen.
    case play(Animation)
    /// Sprechblase zeigen (sofort weiter).
    case say(String)
    /// Beliebiger Code (sofort weiter).
    case run(() -> Void)

    var animation: Animation? {
        switch self {
        case let .walk(_, speed, carry, _): return carry ? .carry : (speed >= 2.2 ? .run : .walk)
        case let .pose(anim, _), let .play(anim): return anim
        case .say, .run: return nil
        }
    }
}

/// Steuert Billy: Position, Haltung, Animation, Handlungskette und freies Herumstreunen.
@MainActor
final class PetController: NSObject, PetViewDelegate {
    let window = PetWindow.make()
    let view = PetView()
    private(set) var sprites: SpriteLibrary

    /// Fußpunkt in globalen Bildschirmkoordinaten.
    private(set) var position: CGPoint
    private(set) var posture: Posture = .stand
    private var animation: Animation = .stand
    private var restAnimation: Animation = .stand
    private var animClock: Double = 0
    private var queue: [PetAction] = []
    private var current: PetAction?
    private var currentElapsed: TimeInterval = 0
    /// Laufender Haltungswechsel (z. B. Hinsetzen).
    private var transition: (anim: Animation, elapsed: TimeInterval, duration: TimeInterval, result: Posture)?
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
        timer = Timer.scheduledTimer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        say("Wuff! Ich bin Billy. 🐾")
        enqueue([.play(.stretch)])
    }

    func applySettings() {
        let scale = Settings.shared.scale
        view.scale = scale
        view.frameSize = sprites.frameSize
        view.groundY = sprites.groundY
        view.proceduralLife = sprites.needsProceduralBob
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

    /// Bricht alles ab, was Billy gerade tut (ein laufender Haltungswechsel darf zu Ende laufen).
    func interrupt() {
        queue.removeAll()
        current = nil
        view.carriedIcon = nil
        lastInteraction = Date()
    }

    /// Ruhehaltung, in die Billy zurückkehrt, wenn nichts zu tun ist.
    func rest(_ animation: Animation) {
        let wasSleeping = restAnimation == .sleep
        restAnimation = animation
        lastInteraction = Date()
        nextIdleDecision = Date().addingTimeInterval(.random(in: 10...20))
        if wasSleeping, animation != .sleep, animation != .lie {
            queue.insert(.play(.stretch), at: 0)
        }
    }

    /// Billy hört zu (Chat geöffnet): zur Maus schauen und Kopf schief legen.
    func listen() {
        guard !isBusy else { return }
        if restAnimation == .sleep { rest(.stand) }
        view.facingLeft = NSEvent.mouseLocation.x < position.x
        enqueue([.play(.tilt)])
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
        let frames = sprites.frames(animation)
        guard let frame = frames.last else { return target }
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
        view.time += dt

        if !dragging { advance(dt: dt) }
        if let until = bubbleUntil, now > until { view.bubbleText = nil; bubbleUntil = nil }
        view.showHeart = heartUntil.map { now < $0 } ?? false
        updateMousePassthrough()
        render()
    }

    private func advance(dt: TimeInterval) {
        // 1. Laufender Haltungswechsel hat Vorrang.
        if var t = transition {
            t.elapsed += dt
            setAnimation(t.anim)
            if t.elapsed >= t.duration {
                posture = t.result
                transition = nil
            } else {
                transition = t
            }
            return
        }

        // 2. Sofort-Aktionen (Sprechen, Code) abarbeiten.
        while current == nil, !queue.isEmpty {
            let next = queue.removeFirst()
            switch next {
            case let .say(text): say(text)
            case let .run(block): block()
            default:
                current = next
                currentElapsed = 0
            }
        }

        // 3. Passt die Haltung? Sonst erst aufstehen, hinsetzen oder hinlegen.
        let desired = current?.animation ?? restAnimation
        if let need = desired.posture, need != posture {
            beginTransition(toward: need)
            return
        }

        guard let action = current else {
            setAnimation(restAnimation)
            idleBehaviour()
            return
        }
        currentElapsed += dt
        switch action {
        case let .walk(target, speed, _, faceLeftOnArrival):
            let dx = target.x - position.x, dy = target.y - position.y
            let dist = hypot(dx, dy)
            setAnimation(action.animation ?? .walk)
            if abs(dx) > 1 { view.facingLeft = dx < 0 }
            // sanft anlaufen und abbremsen
            let ramp = min(1, 0.35 + currentElapsed / 0.3) * min(1, max(0.45, dist / (40 * view.scale)))
            let step = 120 * view.scale * speed * ramp * dt
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
        case let .play(anim):
            setAnimation(anim)
            if anim == .place, view.carriedIcon != nil, currentElapsed >= sprites.duration(of: .place) * 0.6 {
                view.dropCarriedIcon()
            }
            if currentElapsed >= sprites.duration(of: anim) {
                if anim == .place { view.dropCarriedIcon() }
                finishAction()
            }
        case .say, .run:
            finishAction()
        }
    }

    private func beginTransition(toward target: Posture) {
        let step: (Animation, Posture)
        switch (posture, target) {
        case (.stand, _): step = (.sitDown, .sit)
        case (.sit, .stand): step = (.standUp, .stand)
        case (.sit, _): step = (.lieDown, .lie)
        case (.lie, _): step = (.getUp, .sit)
        }
        let duration = sprites.has(step.0) ? sprites.duration(of: step.0) : 0
        if duration <= 0 {
            posture = step.1          // Foto-Sets ohne Übergang: weich überblenden
            view.crossfade()
            return
        }
        transition = (step.0, 0, duration, step.1)
        setAnimation(step.0)
    }

    private func finishAction() {
        current = nil
        currentElapsed = 0
    }

    private func setAnimation(_ anim: Animation) {
        guard anim != animation else { return }
        view.crossfade()
        animation = anim
        animClock = 0
    }

    /// Freies Verhalten, wenn nichts in der Warteschlange steht.
    private func idleBehaviour() {
        let now = Date()
        if now.timeIntervalSince(lastInteraction) > 180, restAnimation != .sleep {
            restAnimation = .sleep
            return
        }
        guard restAnimation != .sleep else { return }

        // Maus in der Nähe? Billy schaut hin.
        let mouse = NSEvent.mouseLocation
        let mouseNear = hypot(mouse.x - position.x, mouse.y - position.y) < 260 * view.scale
        if mouseNear, abs(mouse.x - position.x) > 25 {
            view.facingLeft = mouse.x < position.x
        }

        guard autonomous, now >= nextIdleDecision else { return }
        nextIdleDecision = now.addingTimeInterval(.random(in: 6...14))
        if mouseNear, Int.random(in: 0..<3) == 0 {
            enqueue([.play(.tilt)])
            lastInteraction = now.addingTimeInterval(-60)
            return
        }
        switch Int.random(in: 0..<12) {
        case 0...3:
            restAnimation = .stand
            enqueue([.walk(to: randomSpot())])
            lastInteraction = now.addingTimeInterval(-60)
        case 4:
            restAnimation = .stand
            enqueue([.walk(to: randomSpot(), speed: 2.6), .play(.stretch)])
            lastInteraction = now.addingTimeInterval(-60)
        case 5...6:
            restAnimation = .sit
        case 7:
            restAnimation = .lie
        case 8:
            enqueue([.pose(.sniff, duration: 2.5)])
        case 9:
            enqueue([.play(.stretch)])
        default:
            restAnimation = .stand
        }
    }

    private func render() {
        let frames = sprites.frames(animation)
        guard !frames.isEmpty else { return }
        if animation.isOneShot || transition != nil {
            let index = min(Int(animClock * animation.fps), frames.count - 1)
            view.setFrame(frames[index], animation: animation)
        } else {
            let phase = animClock / animation.cycleSeconds * Double(frames.count)
            let index = Int(phase) % frames.count
            // Foto-Sets haben wenige Bilder: am Ende jedes Bildes ins nächste überblenden
            let fraction = phase - floor(phase)
            let blend = sprites.needsProceduralBob && frames.count > 1 ? max(0, (fraction - 0.55) / 0.45) : 0
            view.setFrame(frames[index], next: frames[(index + 1) % frames.count], blend: CGFloat(blend), animation: animation)
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
            rest(.stand)
            say("Hm? Ich bin wach! 🐶")
            return
        }
        guard !isBusy else { return }
        heart()
        enqueue([posture == .stand ? .pose(.hop, duration: 1.2) : .pose(.happy, duration: 1.4)])
        say(["Wuff! ❤️", "Kraulen! 🥰", "Nochmal!", "Hihi, das kitzelt!"].randomElement()!)
    }

    func petViewDragged(_ view: PetView, by delta: CGPoint) {
        if !dragging {
            dragging = true
            transition = nil
            setAnimation(.dangle)
        }
        position = CGPoint(x: position.x + delta.x, y: position.y + delta.y)
        updateWindowPosition()
    }

    func petViewDragEnded(_ view: PetView) {
        dragging = false
        posture = .stand
        position = clampToScreen(position)
        updateWindowPosition()
        view.bounce()
        lastInteraction = Date()
        if restAnimation == .sleep || restAnimation == .lie { restAnimation = .stand }
        say(["Huch!", "Wo bin ich? 🐾", "Nochmal fliegen!"].randomElement()!)
    }

    func petViewMenu(_ view: PetView) -> NSMenu? {
        menuProvider?()
    }
}
