import XCTest
@testable import BillyCore

final class FileCategorizerTests: XCTestCase {
    func testCategories() {
        let cases: [(String, DesktopCategory)] = [
            ("Bildschirmfoto 2026-09-25 um 10.01.02.png", .screenshots),
            ("Screenshot 2026-09-16 at 14.44.44.png", .screenshots),
            ("Bildschirmaufnahme 2026-09-25.mov", .screenshots),
            ("Screenshot-Notizen.txt", .documents),
            ("Urlaub.HEIC", .images),
            ("Rechnung.pdf", .documents),
            ("Tabelle.xlsx", .documents),
            ("Song.mp3", .music),
            ("Clip.mp4", .videos),
            ("Backup.tar.gz", .archives),
            ("Installer.dmg", .installers),
            ("script.py", .code),
            ("README", .other),
            ("Link.webloc", .other),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(FileCategorizer.category(forFileName: name), expected, name)
        }
    }

    func testFolderNamesAreUnique() {
        let names = DesktopCategory.allCases.map(\.folderName)
        XCTAssertEqual(Set(names).count, names.count)
    }
}
