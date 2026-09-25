import AppKit

enum Animation: String, CaseIterable {
    case walk, carry, stand, sit, bark, happy, lie, sleep, sniff

    /// Bilder pro Sekunde.
    var fps: Double {
        switch self {
        case .walk, .carry: return 10
        case .happy: return 8
        case .sniff: return 6
        case .stand, .sit, .bark: return 4
        case .lie: return 1.5
        case .sleep: return 1
        }
    }

    /// Ersatz, falls ein Foto-Set eine Pose nicht enthält.
    var fallback: Animation? {
        switch self {
        case .carry: return .walk
        case .happy, .bark: return .sit
        case .sleep: return .lie
        case .sniff, .sit, .lie, .walk: return .stand
        case .stand: return nil
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

    func frames(_ animation: Animation) -> [SpriteFrame] {
        var current: Animation? = animation
        while let a = current {
            if let frames = animations[a] { return frames }
            current = a.fallback
        }
        return animations[.walk] ?? []
    }

    /// Mitgelieferte Zeichnung: im App-Bundle oder – bei `swift run` – im Repo.
    static func bundledDirectory() -> URL? {
        let fm = FileManager.default
        if let res = Bundle.main.resourceURL?.appendingPathComponent("Sprites"),
           fm.fileExists(atPath: res.appendingPathComponent("sprites.json").path) {
            return res
        }
        if let env = ProcessInfo.processInfo.environment["BILLY_SPRITES"] {
            return URL(fileURLWithPath: env)
        }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Resources/Sprites")
            if fm.fileExists(atPath: candidate.appendingPathComponent("sprites.json").path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    static var hasPhotoSkin: Bool {
        FileManager.default.fileExists(atPath: Settings.photoSpritesDirectory.appendingPathComponent("sprites.json").path)
    }

    /// Lädt je nach Einstellung Foto- oder Zeichen-Sprites (mit Rückfall auf die Zeichnung).
    @MainActor
    static func loadPreferred() -> SpriteLibrary? {
        if Settings.shared.skin == "photo", hasPhotoSkin,
           let library = try? SpriteLibrary(directory: Settings.photoSpritesDirectory) {
            return library
        }
        guard let dir = bundledDirectory() else { return nil }
        return try? SpriteLibrary(directory: dir)
    }
}
