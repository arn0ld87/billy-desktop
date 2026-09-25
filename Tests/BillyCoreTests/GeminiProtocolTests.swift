import XCTest
@testable import BillyCore

final class GeminiProtocolTests: XCTestCase {
    func testRequestBodyMapsRolesAndSchema() throws {
        let body = GeminiProtocol.requestBody(systemPrompt: "Du bist Billy.", history: [
            ChatTurn(role: .user, text: "Hallo"),
            ChatTurn(role: .assistant, text: "Wuff!"),
            ChatTurn(role: .user, text: "Räum auf"),
        ])
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.map { $0["role"] as? String }, ["user", "model", "user"])

        let config = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual(config["responseMimeType"] as? String, "application/json")
        let schema = try XCTUnwrap(config["responseJsonSchema"] as? [String: Any])
        let props = try XCTUnwrap(schema["properties"] as? [String: Any])
        let action = try XCTUnwrap(props["action"] as? [String: Any])
        let actions = try XCTUnwrap(action["enum"] as? [String])
        XCTAssertEqual(actions.first, "none")
        XCTAssertTrue(actions.contains("tidyDesktop"))

        // muss sich als JSON serialisieren lassen
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
        XCTAssertTrue(GeminiProtocol.endpoint(model: "gemini-3.5-flash-lite").absoluteString
            .hasSuffix("/v1beta/models/gemini-3.5-flash-lite:generateContent"))
    }

    func testParseStructuredReplyWithAction() throws {
        let data = Data("""
        {"candidates":[{"content":{"role":"model","parts":[
          {"text":"Denke nach …","thought":true},
          {"text":"{\\"reply\\":\\"Wuff, ich räum auf!\\",\\"action\\":\\"tidyDesktop\\"}"}
        ]},"finishReason":"STOP"}]}
        """.utf8)
        let reply = try GeminiProtocol.parse(data)
        XCTAssertEqual(reply, ChatReply(text: "Wuff, ich räum auf!", command: .tidyDesktop))
    }

    func testParseNoneActionAndPlainText() throws {
        let none = Data(#"{"candidates":[{"content":{"parts":[{"text":"{\"reply\":\"Hallo!\",\"action\":\"none\"}"}]}}]}"#.utf8)
        XCTAssertEqual(try GeminiProtocol.parse(none), ChatReply(text: "Hallo!", command: nil))

        let plain = Data(#"{"candidates":[{"content":{"parts":[{"text":"Nur Text"}]}}]}"#.utf8)
        XCTAssertEqual(try GeminiProtocol.parse(plain), ChatReply(text: "Nur Text", command: nil))
    }

    func testParseBlockedAndErrors() {
        let blocked = Data(#"{"promptFeedback":{"blockReason":"SAFETY"}}"#.utf8)
        XCTAssertThrowsError(try GeminiProtocol.parse(blocked)) {
            XCTAssertEqual($0 as? GeminiProtocol.ParseError, .blocked("SAFETY"))
        }
        let safety = Data(#"{"candidates":[{"content":{"parts":[]},"finishReason":"SAFETY"}]}"#.utf8)
        XCTAssertThrowsError(try GeminiProtocol.parse(safety)) {
            XCTAssertEqual($0 as? GeminiProtocol.ParseError, .blocked("SAFETY"))
        }
        let error = Data(#"{"error":{"code":400,"message":"API key not valid."}}"#.utf8)
        XCTAssertEqual(GeminiProtocol.errorMessage(error), "API key not valid.")
    }
}
