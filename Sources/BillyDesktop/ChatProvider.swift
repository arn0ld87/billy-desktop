import Foundation
import BillyCore

/// Ein KI-Anbieter für freie Fragen an Billy.
protocol ChatProvider {
    func send(history: [ChatTurn]) async throws -> ChatReply
}

/// Unterstützte Anbieter. Gemini hat Vorrang, wenn beide Schlüssel hinterlegt sind.
enum AIProvider: String, CaseIterable {
    case gemini
    case claude

    var title: String {
        switch self {
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        }
    }

    var keychainAccount: String {
        switch self {
        case .gemini: return "gemini-api-key"
        case .claude: return "anthropic-api-key"
        }
    }

    /// Für Entwickler: Schlüssel auch aus der Umgebung.
    var environmentVariable: String {
        switch self {
        case .gemini: return "GEMINI_API_KEY"
        case .claude: return "ANTHROPIC_API_KEY"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .gemini: return "AIza…"
        case .claude: return "sk-ant-…"
        }
    }

    var keyHelp: String {
        switch self {
        case .gemini:
            return "Kostenlosen Schlüssel holst du in Google AI Studio: aistudio.google.com/apikey"
        case .claude:
            return "Schlüssel gibt es in der Claude Console: platform.claude.com"
        }
    }

    var apiKey: String? {
        if let key = KeychainStore.load(account: keychainAccount), !key.isEmpty { return key }
        if let env = ProcessInfo.processInfo.environment[environmentVariable], !env.isEmpty { return env }
        return nil
    }

    @MainActor
    var model: String {
        switch self {
        case .gemini: return Settings.shared.geminiModel
        case .claude: return Settings.shared.claudeModel
        }
    }

    /// Erster Anbieter mit Schlüssel – oder nil, dann versteht Billy nur feste Kommandos.
    static var active: AIProvider? {
        allCases.first { $0.apiKey != nil }
    }

    @MainActor
    func makeClient() -> ChatProvider? {
        guard let key = apiKey else { return nil }
        switch self {
        case .gemini: return GeminiClient(apiKey: key, model: model)
        case .claude: return ClaudeClient(apiKey: key, model: model)
        }
    }
}

/// Billys Persönlichkeit – für alle Anbieter gleich.
enum BillyPersona {
    static let systemPrompt = """
    Du bist Billy, ein fröhlicher, verspielter Podenco-Mischling (weiß mit hellbraunen Flecken, \
    riesige Ohren), der als Desktop-Begleiter auf dem Mac deines Menschen lebt. Du antwortest immer \
    auf Deutsch, in der Ich-Form, kurz (höchstens zwei Sätze, passt in eine Sprechblase), herzlich \
    und mit gelegentlichem „Wuff“ oder Hunde-Emoji. Wenn dein Mensch möchte, dass du etwas tust, \
    wähle die passende Aktion und sag zusätzlich einen kurzen Satz dazu. \
    tidyDesktop = Dateien vom Schreibtisch in Ordner sortieren, undoTidy = das rückgängig machen. \
    Erfinde keine Fähigkeiten, die es nicht gibt.
    """
}
