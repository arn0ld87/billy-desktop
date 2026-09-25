import XCTest
@testable import BillyCore

final class CommandParserTests: XCTestCase {
    func testGermanCommands() {
        let cases: [(String, BillyCommand)] = [
            ("Kannst du meinen Schreibtisch aufräumen?", .tidyDesktop),
            ("Räum mal auf, Billy!", .tidyDesktop),
            ("Mach das Aufräumen rückgängig", .undoTidy),
            ("Sitz!", .sit),
            ("Platz", .lieDown),
            ("Leg dich hin", .lieDown),
            ("Gute Nacht Billy", .sleep),
            ("Komm her", .come),
            ("Gassi?", .walk),
            ("Gib Laut!", .speak),
            ("Leckerli für dich", .treat),
            ("Braver Hund", .treat),
            ("Bleib!", .stay),
            ("Aus!", .stay),
            ("Hallo Billy", .hello),
            ("Hilfe", .help),
            ("Welche Kommandos kennst du?", .help),
        ]
        for (text, expected) in cases {
            XCTAssertEqual(CommandParser.parse(text), expected, text)
        }
    }

    func testEnglishCommands() {
        XCTAssertEqual(CommandParser.parse("Can you clean my desktop"), .tidyDesktop)
        XCTAssertEqual(CommandParser.parse("undo that"), .undoTidy)
        XCTAssertEqual(CommandParser.parse("sit"), .sit)
        XCTAssertEqual(CommandParser.parse("come here"), .come)
        XCTAssertEqual(CommandParser.parse("hi"), .hello)
    }

    func testWholeWordKeywordsDoNotMatchInsideWords() {
        XCTAssertNotEqual(CommandParser.parse("Öffne den Ordner"), .tidyDesktop)
        XCTAssertNil(CommandParser.parse("Das Aussehen ist toll"))
        XCTAssertNil(CommandParser.parse("Wie geht's dir?"))
    }

    func testNormalization() {
        XCTAssertEqual(CommandParser.normalize("  RÄUM   auf!! "), "raum auf")
        XCTAssertEqual(CommandParser.normalize("Bei Fuß"), "bei fuss")
    }
}
