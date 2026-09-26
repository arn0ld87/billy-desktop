import XCTest
@testable import BillyCore

final class TidyTests: XCTestCase {
    private var desktop: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        desktop = fm.temporaryDirectory.appendingPathComponent("BillyTests-\(UUID().uuidString)/Desktop", isDirectory: true)
        try fm.createDirectory(at: desktop, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: desktop.deletingLastPathComponent())
    }

    private func touch(_ name: String, _ content: String = "x") throws {
        try Data(content.utf8).write(to: desktop.appendingPathComponent(name))
    }

    private func items() throws -> [DesktopItem] {
        try fm.contentsOfDirectory(at: desktop, includingPropertiesForKeys: [.isDirectoryKey]).map {
            DesktopItem(url: $0, isDirectory: (try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
        }
    }

    func testUniqueNamer() {
        XCTAssertEqual(UniqueNamer.candidate(for: "Bild.png", attempt: 1), "Bild.png")
        XCTAssertEqual(UniqueNamer.candidate(for: "Bild.png", attempt: 2), "Bild 2.png")
        XCTAssertEqual(UniqueNamer.candidate(for: "README", attempt: 3), "README 3")
        let folder = URL(fileURLWithPath: "/tmp/x")
        let taken: Set<String> = ["/tmp/x/a.txt", "/tmp/x/a 2.txt"]
        XCTAssertEqual(UniqueNamer.uniqueURL(in: folder, fileName: "a.txt") { taken.contains($0.path) }.lastPathComponent, "a 3.txt")
    }

    func testPlanSkipsFoldersHiddenAndDownloads() throws {
        try touch("Screenshot 2026-09-16 at 14.44.44.png")
        try touch("Rechnung.pdf")
        try touch(".DS_Store")
        try touch("Film.mp4.crdownload")
        try fm.createDirectory(at: desktop.appendingPathComponent("Projekte"), withIntermediateDirectories: true)
        try fm.createDirectory(at: desktop.appendingPathComponent("Tool.app"), withIntermediateDirectories: true)

        let plan = TidyPlanner.plan(items: try items(), desktop: desktop) { self.fm.fileExists(atPath: $0.path) }
        XCTAssertEqual(plan.moves.map(\.source.lastPathComponent).sorted(),
                       ["Rechnung.pdf", "Screenshot 2026-09-16 at 14.44.44.png"])
        XCTAssertEqual(Set(plan.folders.map(\.lastPathComponent)), ["Screenshots", "Dokumente"])
        XCTAssertEqual(plan.summaryLines, ["1 × Screenshots", "1 × Dokumente"])
    }

    func testPlanAvoidsCollisions() throws {
        let docs = desktop.appendingPathComponent("Dokumente")
        try fm.createDirectory(at: docs, withIntermediateDirectories: true)
        try Data("alt".utf8).write(to: docs.appendingPathComponent("Notiz.txt"))
        try touch("Notiz.txt", "neu")

        let plan = TidyPlanner.plan(items: try items(), desktop: desktop) { self.fm.fileExists(atPath: $0.path) }
        XCTAssertEqual(plan.moves.first?.destination.lastPathComponent, "Notiz 2.txt")
    }

    func testExecuteAndUndoRestoresEverything() throws {
        try touch("Screenshot 1.png", "a")
        try touch("Brief.docx", "b")
        try touch("Musik.mp3", "c")
        let plan = TidyPlanner.plan(items: try items(), desktop: desktop) { self.fm.fileExists(atPath: $0.path) }

        let executor = TidyExecutor(fileManager: fm)
        for move in plan.moves { try executor.perform(move) }
        XCTAssertTrue(fm.fileExists(atPath: desktop.appendingPathComponent("Screenshots/Screenshot 1.png").path))
        XCTAssertTrue(fm.fileExists(atPath: desktop.appendingPathComponent("Dokumente/Brief.docx").path))
        XCTAssertFalse(fm.fileExists(atPath: desktop.appendingPathComponent("Musik.mp3").path))
        XCTAssertEqual(executor.journal.records.count, 3)
        XCTAssertEqual(executor.journal.createdFolders.count, 3)

        // Journal übersteht Speichern/Laden
        let store = JournalStore(url: desktop.deletingLastPathComponent().appendingPathComponent("journal.json"))
        try store.save(executor.journal)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.records, executor.journal.records)

        let result = TidyExecutor.undo(loaded, fileManager: fm)
        XCTAssertEqual(result.restored, 3)
        XCTAssertTrue(result.failed.isEmpty)
        let remaining = try fm.contentsOfDirectory(atPath: desktop.path).sorted()
        XCTAssertEqual(remaining, ["Brief.docx", "Musik.mp3", "Screenshot 1.png"])
        XCTAssertEqual(try String(contentsOf: desktop.appendingPathComponent("Brief.docx"), encoding: .utf8), "b")
    }

    func testUndoKeepsFoldersThatAreNotEmptyAndNeverOverwrites() throws {
        try touch("Brief.docx", "original")
        let plan = TidyPlanner.plan(items: try items(), desktop: desktop) { self.fm.fileExists(atPath: $0.path) }
        let executor = TidyExecutor(fileManager: fm)
        for move in plan.moves { try executor.perform(move) }

        // Nutzer legt inzwischen eine neue Datei gleichen Namens an und etwas in den Ordner.
        try touch("Brief.docx", "neu")
        try Data("y".utf8).write(to: desktop.appendingPathComponent("Dokumente/Eigenes.pdf"))

        let result = TidyExecutor.undo(executor.journal, fileManager: fm)
        XCTAssertEqual(result.restored, 1)
        XCTAssertEqual(try String(contentsOf: desktop.appendingPathComponent("Brief.docx"), encoding: .utf8), "neu")
        XCTAssertEqual(try String(contentsOf: desktop.appendingPathComponent("Brief 2.docx"), encoding: .utf8), "original")
        XCTAssertTrue(fm.fileExists(atPath: desktop.appendingPathComponent("Dokumente/Eigenes.pdf").path))
    }

    func testJournalIsSavedAfterEveryMoveSoPartialRunsCanBeUndone() throws {
        try touch("Brief.docx", "b")
        try touch("Song.mp3", "c")
        let plan = TidyPlanner.plan(items: try items(), desktop: desktop) { self.fm.fileExists(atPath: $0.path) }
        let store = JournalStore(url: desktop.deletingLastPathComponent().appendingPathComponent("journal.json"))
        let executor = TidyExecutor(fileManager: fm)
        executor.onRecord = { try? store.save($0) }

        // Abbruch nach der ersten Datei: Das Journal liegt trotzdem schon auf der Platte.
        try executor.perform(plan.moves[0])
        let saved = try XCTUnwrap(store.load())
        XCTAssertEqual(saved.records.count, 1)
        XCTAssertEqual(saved.createdFolders.count, 1)

        let result = TidyExecutor.undo(saved, fileManager: fm)
        XCTAssertEqual(result.restored, 1)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: desktop.path).sorted(), ["Brief.docx", "Song.mp3"])
    }

    func testPerformThrowsWhenSourceVanished() throws {
        try touch("Weg.txt")
        let plan = TidyPlanner.plan(items: try items(), desktop: desktop) { self.fm.fileExists(atPath: $0.path) }
        try fm.removeItem(at: desktop.appendingPathComponent("Weg.txt"))
        XCTAssertThrowsError(try TidyExecutor(fileManager: fm).perform(plan.moves[0]))
    }
}
