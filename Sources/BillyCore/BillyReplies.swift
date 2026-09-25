import Foundation

/// Billys Sprechblasen-Texte.
public enum BillyReplies {
    public static func lines(for command: BillyCommand) -> [String] {
        switch command {
        case .tidyDesktop: return ["Wuff! Ich räum auf! 🧹", "Bin schon dabei! 🐾", "Schnüffel … da liegt ja einiges rum!"]
        case .undoTidy: return ["Okay, ich leg alles zurück. 🐾", "Wuff – alles wieder wie vorher!"]
        case .sit: return ["Sitz! ✔︎", "Sitze schon. Leckerli? 👀", "Brav gesessen!"]
        case .lieDown: return ["Platz! 🐕", "Ich mach's mir gemütlich.", "Liege schon!"]
        case .sleep: return ["Gute Nacht … 💤", "Ein kleines Nickerchen …", "Zzz …"]
        case .come: return ["Ich komme! 🐾", "Bin gleich da!", "Wuff, hier bin ich!"]
        case .walk: return ["Gassi! 🎉", "Juhu, rumlaufen!", "Ich dreh 'ne Runde!"]
        case .speak: return ["Wuff! Wuff!", "WAU!", "Wuff wuff wuff!"]
        case .treat: return ["Mmmh, Leckerli! ❤️", "Danke! ❤️", "Ich bin der Bravste!"]
        case .stay: return ["Ich bleib hier.", "Okay, ich rühr mich nicht.", "Bleibe!"]
        case .play: return ["Spielen! 🎾", "Ich lauf wieder frei rum!", "Zoomies! 💨"]
        case .hello: return ["Hallo! 🐾", "Wuff! Schön, dass du da bist!", "Hey du! ❤️"]
        case .help: return [helpText]
        }
    }

    public static let helpText = """
    Sag mir z. B.: „Räum meinen Schreibtisch auf“, „Rückgängig“, „Sitz“, „Platz“, \
    „Schlaf“, „Komm“, „Gassi“, „Gib Laut“, „Leckerli“, „Bleib“ oder „Spiel“.
    """

    public static let notUnderstood = [
        "Wuff? Das versteh ich nicht. Sag „Hilfe“, dann zeig ich dir, was ich kann.",
        "Hä? 🐶 Probier mal „Räum auf“ oder „Sitz“.",
    ]

    public static func tidySummary(moved: Int) -> String {
        switch moved {
        case 0: return "Dein Schreibtisch ist schon blitzblank! ✨"
        case 1: return "Fertig! 1 Datei aufgeräumt. 🐾"
        default: return "Fertig! \(moved) Dateien aufgeräumt. 🐾"
        }
    }

    public static func random<G: RandomNumberGenerator>(for command: BillyCommand, using generator: inout G) -> String {
        lines(for: command).randomElement(using: &generator) ?? "Wuff!"
    }

    public static func random(for command: BillyCommand) -> String {
        var generator = SystemRandomNumberGenerator()
        return random(for: command, using: &generator)
    }
}
