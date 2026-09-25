import AppKit

/// Grundhaltung – zwischen Haltungen spielt Billy Übergangsanimationen.
enum Posture {
    case stand, sit, lie
}

enum Animation: String, CaseIterable {
    case walk, carry, run, stand, sit, happy, hop, bark, lie, sleep, sniff
    case tilt, stretch, sitDown, standUp, lieDown, getUp, pick, place, dangle

    /// Bilder pro Sekunde.
    var fps: Double {
        switch self {
        case .walk, .carry: return 12
        case .run: return 14
        case .happy, .hop, .pick, .place: return 10
        case .sniff, .tilt, .stretch: return 8
        case .sitDown, .standUp, .lieDown, .getUp: return 14
        case .bark, .dangle: return 6
        case .stand, .sit: return 4
        case .lie: return 3
        case .sleep: return 2
        }
    }

    /// Dauer eines Schleifendurchlaufs – unabhängig davon, wie viele Bilder ein Set hat
    /// (Foto-Sets mit 4 Laufbildern laufen so genauso schnell wie die Zeichnung mit 12).
    var cycleSeconds: Double {
        switch self {
        case .walk, .carry, .sniff: return 1.0
        case .run: return 0.57
        case .stand, .sit, .sleep: return 4.0
        case .happy, .hop: return 0.8
        case .bark, .dangle: return 0.67
        case .lie: return 2.67
        default: return 1.0
        }
    }

    /// Einmalige Animationen (danach geht es weiter), alle anderen laufen in Schleife.
    var isOneShot: Bool {
        switch self {
        case .sitDown, .standUp, .lieDown, .getUp, .pick, .place, .stretch, .tilt: return true
        default: return false
        }
    }

    /// Haltung, die diese Animation voraussetzt (nil = egal).
    var posture: Posture? {
        switch self {
        case .walk, .carry, .run, .stand, .hop, .sniff, .tilt, .stretch, .pick, .place: return .stand
        case .sit, .happy, .bark: return .sit
        case .lie, .sleep: return .lie
        case .sitDown, .standUp, .lieDown, .getUp, .dangle: return nil
        }
    }

    /// Ersatz, falls ein Foto-Set eine Pose nicht enthält. Übergänge ohne Ersatz werden übersprungen.
    var fallback: Animation? {
        switch self {
        case .carry, .run: return .walk
        case .happy, .bark: return .sit
        case .hop, .sniff, .tilt, .walk: return .stand
        case .sleep: return .lie
        case .lie: return .sit
        case .sit: return .stand
        case .pick, .place: return .sniff
        case .dangle: return .happy
        case .stand, .stretch, .sitDown, .standUp, .lieDown, .getUp: return nil
        }
    }
}

/// Ein Einzelbild samt Ankerpunkten (in Punkten, Ursprung oben links im Frame).
struct SpriteFrame {
    let image: NSImage
    let bitmap: NSBitmapImageRep?
    let anchors: [String: CGPoint]

    func anchor(_ name: String) -> CGPoint {
        anchors[name] ?? anchors["head"] ?? .zero
    }

    /// Ist der Punkt (Frame-Koordinaten, oben links) nicht transparent?
    func isOpaque(at point: CGPoint, frameSize: CGSize) -> Bool {
        guard let bitmap else { return true }
        let sx = CGFloat(bitmap.pixelsWide) / frameSize.width
        let sy = CGFloat(bitmap.pixelsHigh) / frameSize.height
        let x = Int(point.x * sx), y = Int(point.y * sy)
        guard x >= 0, y >= 0, x < bitmap.pixelsWide, y < bitmap.pixelsHigh else { return false }
        return (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.15
    }
}

/// Lädt Sprites aus einem Ordner mit `sprites.json` + PNGs.
final class SpriteLibrary {
    let frameSize: CGSize
    let groundY: CGFloat
    /// Foto-Sets haben oft nur ein Bild pro Pose – dann wippt Billy beim Laufen.
    let needsProceduralBob: Bool
    private let animations: [Animation: [SpriteFrame]]

    private struct Meta: Decodable {
        struct Frame: Decodable {
            let file: String
            let anchors: [String: [Double]]
        }
        let frameSize: [Double]
        let groundY: Double
        let animations: [String: [Frame]]
    }

    init(directory: URL) throws {
        let data = try Data(contentsOf: directory.appendingPathComponent("sprites.json"))
        let meta = try JSONDecoder().decode(Meta.self, from: data)
        frameSize = CGSize(width: meta.frameSize[0], height: meta.frameSize[1])
        groundY = CGFloat(meta.groundY)
        var minFrames = Int.max
        var animations: [Animation: [SpriteFrame]] = [:]
        for (name, frames) in meta.animations {
            guard let animation = Animation(rawValue: name) else { continue }
            let loaded: [SpriteFrame] = frames.compactMap { frame in
                guard let image = NSImage(contentsOf: directory.appendingPathComponent(frame.file)) else { return nil }
                let bitmap = image.representations.compactMap { $0 as? NSBitmapImageRep }.first
                image.size = CGSize(width: meta.frameSize[0], height: meta.frameSize[1])
                var anchors: [String: CGPoint] = [:]
                for (key, value) in frame.anchors where value.count == 2 {
                    anchors[key] = CGPoint(x: value[0], y: value[1])
                }
                return SpriteFrame(image: image, bitmap: bitmap, anchors: anchors)
            }
            if !loaded.isEmpty {
                animations[animation] = loaded
                if animation == .walk { minFrames = min(minFrames, loaded.count) }
            }
        }
        guard animations[.stand] != nil || animations[.walk] != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.animations = animations
        needsProceduralBob = minFrames < 4
    }

    /// Hat das Set eigene Bilder für genau diese Animation?
    func has(_ animation: Animation) -> Bool {
        animations[animation] != nil
    }

    /// Dauer einer Einmal-Animation (0, wenn sie im Set fehlt und keinen Ersatz hat).
    func duration(of animation: Animation) -> TimeInterval {
        var current: Animation? = animation
        while let a = current {
            if let frames = animations[a] { return Double(frames.count) / animation.fps }
            current = a.fallback
        }
        return 0
    }

    func frames(_ animation: Animation) -> [SpriteFrame] {
        var current: Animation? = animation
        while let a = current {
            if let frames = animations[a] { return frames }
            current = a.fallback
        }
        return animations[.walk] ?? []
    }

    /// Mitgelieferter Sprite-Ordner (`Sprites` = Zeichnung, `PhotoSprites` = Fotos):
    /// im App-Bundle oder – bei `swift run` – im Repo.
    static func bundledDirectory(_ name: String = "Sprites") -> URL? {
        let fm = FileManager.default
        func valid(_ url: URL) -> Bool { fm.fileExists(atPath: url.appendingPathComponent("sprites.json").path) }
        if let res = Bundle.main.resourceURL?.appendingPathComponent(name), valid(res) {
            return res
        }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Resources/\(name)")
            if valid(candidate) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    /// Foto-Sprites: eigene aus dem Support-Ordner, sonst die mitgelieferten.
    static var photoDirectory: URL? {
        let own = Settings.photoSpritesDirectory
        if FileManager.default.fileExists(atPath: own.appendingPathComponent("sprites.json").path) { return own }
        return bundledDirectory("PhotoSprites")
    }

    static var hasPhotoSkin: Bool { photoDirectory != nil }

    /// Lädt je nach Einstellung Foto- oder Zeichen-Sprites (mit Rückfall auf die Zeichnung).
    @MainActor
    static func loadPreferred() -> SpriteLibrary? {
        if Settings.shared.skin != "drawn", let dir = photoDirectory,
           let library = try? SpriteLibrary(directory: dir) {
            return library
        }
        guard let dir = bundledDirectory() else { return nil }
        return try? SpriteLibrary(directory: dir)
    }

    @MainActor
    static var isShowingPhotos: Bool {
        Settings.shared.skin != "drawn" && hasPhotoSkin
    }
}
