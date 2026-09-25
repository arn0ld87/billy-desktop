import Foundation

/// Ein Gesprächsschritt im KI-Chat.
public struct ChatTurn: Equatable, Sendable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// Antwort eines KI-Anbieters: Sprechblasen-Text plus höchstens eine vorgeschlagene Aktion.
public struct ChatReply: Equatable, Sendable {
    public let text: String
    public let command: BillyCommand?

    public init(text: String, command: BillyCommand?) {
        self.text = text
        self.command = command
    }
}

/// Anfrage und Antwort der Gemini-API (`models/{model}:generateContent`), ohne Netzwerkcode.
///
/// Gemini antwortet per strukturierter Ausgabe (JSON-Schema) mit `{"reply": …, "action": …}`.
/// `action` stammt aus einer festen Liste – die KI kann Billy also nichts Unbekanntes tun lassen.
public enum GeminiProtocol {
    public static let noAction = "none"

    public static func endpoint(model: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
    }

    public static func requestBody(systemPrompt: String, history: [ChatTurn]) -> [String: Any] {
        let actions = [noAction] + BillyCommand.allCases.map(\.rawValue)
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "reply": [
                    "type": "string",
                    "description": "Billys kurze Antwort für die Sprechblase (Deutsch, höchstens zwei Sätze).",
                ] as [String: Any],
                "action": [
                    "type": "string",
                    "enum": actions,
                    "description": "Aktion, die Billy ausführen soll, oder \"none\".",
                ] as [String: Any],
            ] as [String: Any],
            "required": ["reply", "action"],
        ]
        let contents: [[String: Any]] = history.map { turn in
            [
                "role": turn.role == .user ? "user" : "model",
                "parts": [["text": turn.text]],
            ]
        }
        return [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": contents,
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseJsonSchema": schema,
                "maxOutputTokens": 1024,
            ] as [String: Any],
        ]
    }

    public enum ParseError: Error, Equatable {
        case blocked(String)
        case empty
    }

    /// Liest `candidates[0].content.parts` aus. Gedanken-Teile (`thought: true`) werden übersprungen.
    public static func parse(_ data: Data) throws -> ChatReply {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.empty
        }
        if let feedback = json["promptFeedback"] as? [String: Any], let reason = feedback["blockReason"] as? String {
            throw ParseError.blocked(reason)
        }
        let candidate = (json["candidates"] as? [[String: Any]])?.first
        let parts = ((candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        let text = parts
            .filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            if let reason = candidate?["finishReason"] as? String, reason != "STOP" {
                throw ParseError.blocked(reason)
            }
            throw ParseError.empty
        }
        guard let payload = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            return ChatReply(text: text, command: nil)   // kein JSON: Text trotzdem anzeigen
        }
        let reply = (payload["reply"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let command = (payload["action"] as? String).flatMap(BillyCommand.init(rawValue:))
        return ChatReply(text: reply, command: command)
    }

    /// Fehlermeldung aus einer Nicht-200-Antwort (`{"error": {"message": …}}`).
    public static func errorMessage(_ data: Data) -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return ((json?["error"] as? [String: Any])?["message"] as? String) ?? "unbekannter Fehler"
    }
}
