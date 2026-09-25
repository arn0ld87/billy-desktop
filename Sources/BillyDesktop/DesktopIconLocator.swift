import AppKit

/// Fragt den Finder per AppleScript nach den Positionen der Schreibtisch-Symbole.
/// Ohne Automations-Freigabe liefert er nil – Billy läuft dann zu geschätzten Stellen.
@MainActor
enum DesktopIconLocator {
    private(set) static var lastError: String?

    /// Name → Symbolmitte in globalen Bildschirmkoordinaten (Ursprung unten links).
    static func iconPositions() -> [String: CGPoint]? {
        let source = """
        tell application "Finder"
            set theNames to name of every item of desktop
            set thePositions to desktop position of every item of desktop
        end tell
        set out to ""
        repeat with i from 1 to count of theNames
            set p to item i of thePositions
            set out to out & (item i of theNames) & tab & (item 1 of p as text) & tab & (item 2 of p as text) & linefeed
        end repeat
        return out
        """
        guard let text = run(source) else { return nil }
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 900
        var result: [String: CGPoint] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 3, let x = Double(parts[1]), let y = Double(parts[2]) else { continue }
            // Finder-Koordinaten: Ursprung oben links auf dem Hauptbildschirm.
            result[String(parts[0])] = CGPoint(x: x, y: screenTop - y)
        }
        return result
    }

    /// Setzt die Position eines Schreibtisch-Symbols (globale Koordinaten).
    @discardableResult
    static func setPosition(of name: String, to point: CGPoint) -> Bool {
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 900
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Finder"
            set desktop position of item "\(escaped)" of desktop to {\(Int(point.x)), \(Int(screenTop - point.y))}
        end tell
        """
        return run(source) != nil
    }

    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let output = script.executeAndReturnError(&error)
        if let error {
            lastError = (error[NSAppleScript.errorMessage] as? String) ?? "AppleScript-Fehler"
            return nil
        }
        lastError = nil
        return output.stringValue ?? ""
    }
}
