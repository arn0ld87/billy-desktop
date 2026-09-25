import Foundation

/// Alles, was Billy auf Zuruf kann.
public enum BillyCommand: String, CaseIterable, Codable, Sendable {
    case tidyDesktop
    case undoTidy
    case sit
    case lieDown
    case sleep
    case come
    case walk
    case speak
    case treat
    case stay
    case play
    case hello
    case help
}

/// Erkennt Befehle in deutschem oder englischem Freitext – ganz ohne KI.
///
/// Schlüsselwörter matchen am Wortanfang („aufräum“ trifft „aufräumen“).
/// Ein führendes „=“ verlangt ein ganzes Wort („=aus“ trifft nicht „aussehen“).
public enum CommandParser {
    static let rules: [(BillyCommand, [String])] = [
        (.undoTidy, ["rückgängig", "undo", "wiederherstell", "zurücklegen", "restore", "mach das zurück"]),
        (.tidyDesktop, ["aufräum", "aufgeräum", "räum", "=ordne", "=ordnen", "ordnung", "sortier", "ausmist",
                        "clean", "tidy", "organi", "putz", "declutter"]),
        (.help, ["hilfe", "=help", "was kannst", "befehl", "kommando"]),
        (.sleep, ["schlaf", "sleep", "müde", "gute nacht", "nap", "nicker", "pennen"]),
        (.lieDown, ["platz", "leg dich", "lieg", "lie down", "=down"]),
        (.sit, ["sitz", "=sit", "setz dich"]),
        (.come, ["komm", "=hier", "=come", "=here", "bei fuß", "bei fuss", "zu mir"]),
        (.walk, ["gassi", "lauf", "spazier", "=walk", "renn", "=run", "rumlaufen"]),
        (.speak, ["gib laut", "bell", "wuff", "wau", "speak", "bark"]),
        (.treat, ["leckerli", "treat", "brav", "=fein", "good boy", "guter junge", "guter hund", "keks", "snack"]),
        (.stay, ["bleib", "=stay", "=stop", "=halt", "=aus", "ruhe"]),
        (.play, ["spiel", "=play", "toben", "=frei"]),
        (.hello, ["hallo", "=hi", "=hey", "moin", "servus", "hello", "guten morgen", "guten tag", "na du"]),
    ]

    public static func parse(_ text: String) -> BillyCommand? {
        let padded = " " + normalize(text) + " "
        for (command, keywords) in rules {
            for keyword in keywords {
                if keyword.hasPrefix("=") {
                    if padded.contains(" " + normalize(String(keyword.dropFirst())) + " ") { return command }
                } else if padded.contains(" " + normalize(keyword)) {
                    return command
                }
            }
        }
        return nil
    }

    /// Kleinbuchstaben, ohne Akzente, „ß“ → „ss“, Satzzeichen → Leerzeichen.
    static func normalize(_ text: String) -> String {
        let folded = text
            .replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
        let mapped = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}
