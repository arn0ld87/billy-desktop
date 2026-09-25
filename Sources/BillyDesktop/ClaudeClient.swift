import Foundation
import BillyCore

/// Optionaler Freitext-Chat über die Claude Messages API (roh per URLSession, Swift hat kein offizielles SDK).
///
/// Claude darf Billy nichts direkt tun lassen: Es antwortet mit Text und schlägt höchstens eine
/// Aktion aus einer festen Liste vor (Tool `billy_action`). Aufräumen fragt trotzdem immer nach.
struct ClaudeClient: ChatProvider {
    enum ClientError: LocalizedError {
        case http(Int, String)
        case refused
        case badResponse

        var errorDescription: String? {
            switch self {
            case let .http(code, message): return "Claude-Fehler \(code): \(message)"
            case .refused: return "Claude wollte darauf nicht antworten."
            case .badResponse: return "Unerwartete Antwort von Claude."
            }
        }
    }

    let apiKey: String
    let model: String

    func send(history: [ChatTurn]) async throws -> ChatReply {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let isHaiku = model.contains("haiku")
        let actionProperty: [String: Any] = [
            "type": "string",
            "enum": BillyCommand.allCases.map(\.rawValue),
            "description": "Die Aktion, die Billy ausführen soll.",
        ]
        let inputSchema: [String: Any] = [
            "type": "object",
            "properties": ["action": actionProperty],
            "required": ["action"],
            "additionalProperties": false,
        ]
        let tool: [String: Any] = [
            "name": "billy_action",
            "description": "Lässt Billy eine Aktion auf dem Mac ausführen.",
            "strict": true,
            "input_schema": inputSchema,
        ]
        let messages: [[String: String]] = history.map { ["role": $0.role.rawValue, "content": $0.text] }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": BillyPersona.systemPrompt + " Für Aktionen nutzt du das Tool billy_action.",
            "tools": [tool],
            "messages": messages,
        ]
        if !isHaiku {
            // Kurze Chat-Antworten: wenig Denkaufwand genügt.
            body["output_config"] = ["effort": "low"]
        }
        if model.hasPrefix("claude-opus-5") || model.hasPrefix("claude-fable") {
            // Bei einer Ablehnung serverseitig auf das empfohlene Ersatzmodell ausweichen.
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse }
        guard http.statusCode == 200, let json else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "unbekannt"
            throw ClientError.http(http.statusCode, message)
        }
        if (json["stop_reason"] as? String) == "refusal" { throw ClientError.refused }

        var texts: [String] = []
        var command: BillyCommand?
        for block in json["content"] as? [[String: Any]] ?? [] {
            switch block["type"] as? String {
            case "text":
                if let t = block["text"] as? String { texts.append(t) }
            case "tool_use":
                if block["name"] as? String == "billy_action",
                   let input = block["input"] as? [String: Any],
                   let action = input["action"] as? String {
                    command = BillyCommand(rawValue: action)
                }
            default:
                break
            }
        }
        let text = texts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatReply(text: text, command: command)
    }
}
