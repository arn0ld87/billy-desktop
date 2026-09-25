import Foundation
import BillyCore

/// Freitext-Chat über die Gemini API (`generateContent`, roh per URLSession).
/// Standardmodell: Gemini 3.5 Flash-Lite – günstig, schnell, aktuell.
struct GeminiClient: ChatProvider {
    enum ClientError: LocalizedError {
        case http(Int, String)
        case blocked(String)
        case empty

        var errorDescription: String? {
            switch self {
            case let .http(code, message): return "Gemini-Fehler \(code): \(message)"
            case let .blocked(reason): return "Gemini wollte darauf nicht antworten (\(reason))."
            case .empty: return "Gemini hat nichts geantwortet."
            }
        }
    }

    let apiKey: String
    let model: String

    func send(history: [ChatTurn]) async throws -> ChatReply {
        var request = URLRequest(url: GeminiProtocol.endpoint(model: model))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")   // Schlüssel im Header, nie in der URL
        let body = GeminiProtocol.requestBody(systemPrompt: BillyPersona.systemPrompt, history: history)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.empty }
        guard http.statusCode == 200 else {
            throw ClientError.http(http.statusCode, GeminiProtocol.errorMessage(data))
        }
        do {
            return try GeminiProtocol.parse(data)
        } catch GeminiProtocol.ParseError.blocked(let reason) {
            throw ClientError.blocked(reason)
        } catch {
            throw ClientError.empty
        }
    }
}
