import Foundation

/// Geräusche, die Billy machen kann. Dateien heißen `<rawValue>.m4a` oder `<rawValue>_<n>.m4a`.
public enum SoundEvent: String, CaseIterable, Codable, Sendable {
    case bark      // bellen
    case happy     // fröhliches Kläffen / Jaulen
    case pant      // hecheln
    case whine     // winseln (beim Hochheben)
    case snore     // schnarchen
    case sniff     // schnüffeln
    case yawn      // gähnen
    case drop      // Datei fällt in den Ordner
}

/// Wie gesprächig Billy ist.
public enum SoundLevel: String, CaseIterable, Codable, Sendable {
    /// stumm
    case off
    /// nur als Reaktion auf dich (Kraulen, Kommandos, Aufräumen, Hochheben)
    case reactions
    /// zusätzlich selten und gedämpft von selbst (Schnarchen, Hecheln, …)
    case lively
}

/// Entscheidet, ob und wie laut ein Geräusch gespielt wird – ohne Audio-Code.
public struct SoundPolicy: Sendable {
    public var level: SoundLevel
    /// Grundlautstärke 0…1.
    public var volume: Float
    /// Geräusche aus Eigeninitiative sind deutlich leiser …
    public var ambientFactor: Float = 0.33
    /// … und kommen höchstens alle paar Minuten.
    public var ambientInterval: TimeInterval = 150
    public private(set) var lastAmbient: Date?

    public init(level: SoundLevel, volume: Float) {
        self.level = level
        self.volume = volume
    }

    /// Lautstärke, mit der `event` jetzt gespielt werden soll, oder nil für Stille.
    /// - Parameters:
    ///   - isReaction: Billy reagiert auf dich (sonst: Eigeninitiative).
    ///   - microphoneInUse: Läuft gerade ein Call o. Ä.? Dann ist Billy immer still.
    public mutating func volume(for event: SoundEvent, isReaction: Bool, microphoneInUse: Bool, now: Date = Date()) -> Float? {
        guard level != .off, volume > 0, !microphoneInUse else { return nil }
        if isReaction { return min(1, volume) }
        guard level == .lively else { return nil }
        if let last = lastAmbient, now.timeIntervalSince(last) < ambientInterval { return nil }
        lastAmbient = now
        return min(1, volume) * ambientFactor
    }
}
