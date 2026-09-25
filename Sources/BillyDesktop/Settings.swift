import AppKit

/// Persistente Einstellungen (UserDefaults).
@MainActor
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            "scale": 1.0,
            "alwaysOnTop": true,
            "autonomous": true,
            "claudeModel": "claude-opus-5",
            "geminiModel": "gemini-3.5-flash-lite",
            "skin": "auto",
        ])
    }

    var scale: CGFloat {
        get { CGFloat(defaults.double(forKey: "scale")) }
        set { defaults.set(Double(newValue), forKey: "scale") }
    }

    var alwaysOnTop: Bool {
        get { defaults.bool(forKey: "alwaysOnTop") }
        set { defaults.set(newValue, forKey: "alwaysOnTop") }
    }

    var autonomous: Bool {
        get { defaults.bool(forKey: "autonomous") }
        set { defaults.set(newValue, forKey: "autonomous") }
    }

    /// Modell für den optionalen Claude-Chat (z. B. per `defaults write` änderbar).
    /// Gemini-Modell (Standard: 3.5 Flash-Lite – günstig und aktuell).
    var geminiModel: String {
        defaults.string(forKey: "geminiModel") ?? "gemini-3.5-flash-lite"
    }

    var claudeModel: String {
        defaults.string(forKey: "claudeModel") ?? "claude-opus-5"
    }

    /// "auto" = Fotos, wenn vorhanden, sonst Zeichnung; "photo" = Fotos; "drawn" = Zeichnung.
    var skin: String {
        get { defaults.string(forKey: "skin") ?? "auto" }
        set { defaults.set(newValue, forKey: "skin") }
    }

    nonisolated static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Billy Desktop", isDirectory: true)
    }

    /// Ordner für eigene Foto-Sprites (erzeugt mit tools/photos/import_photos.py) – hat Vorrang vor den mitgelieferten.
    nonisolated static var photoSpritesDirectory: URL {
        supportDirectory.appendingPathComponent("Sprites", isDirectory: true)
    }
}
