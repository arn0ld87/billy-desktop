import Foundation

/// Protokoll eines Aufräumvorgangs, damit er rückgängig gemacht werden kann.
public struct TidyJournal: Codable, Equatable, Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public let source: URL
        public let destination: URL
    }

    public var date: Date
    public var records: [Record]
    public var createdFolders: [URL]

    public init(date: Date = Date(), records: [Record] = [], createdFolders: [URL] = []) {
        self.date = date
        self.records = records
        self.createdFolders = createdFolders
    }

    public var isEmpty: Bool { records.isEmpty }
}

public enum TidyError: Error, Equatable {
    case sourceMissing(String)
}

public struct UndoResult: Equatable, Sendable {
    public var restored: Int = 0
    public var failed: [String] = []
}

/// Führt Verschiebungen aus und protokolliert sie. Überschreibt und löscht nie Nutzerdateien.
public final class TidyExecutor {
    private let fileManager: FileManager
    public private(set) var journal: TidyJournal
    /// Wird nach jeder gelungenen Verschiebung aufgerufen – zum sofortigen Sichern des Journals,
    /// damit Rückgängig auch nach Abbruch oder Absturz mitten im Aufräumen funktioniert.
    public var onRecord: ((TidyJournal) -> Void)?

    public init(fileManager: FileManager = .default, date: Date = Date()) {
        self.fileManager = fileManager
        self.journal = TidyJournal(date: date)
    }

    /// Legt einen Zielordner an, falls er fehlt.
    public func ensureFolder(_ folder: URL) throws {
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue { return }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        journal.createdFolders.append(folder)
    }

    /// Verschiebt eine Datei. Ist das Ziel inzwischen belegt, wird ein neuer Name gewählt.
    @discardableResult
    public func perform(_ move: TidyMove) throws -> URL {
        guard fileManager.fileExists(atPath: move.source.path) else {
            throw TidyError.sourceMissing(move.source.lastPathComponent)
        }
        try ensureFolder(move.folder)
        let target = UniqueNamer.uniqueURL(in: move.folder, fileName: move.destination.lastPathComponent) {
            fileManager.fileExists(atPath: $0.path)
        }
        try fileManager.moveItem(at: move.source, to: target)
        journal.records.append(.init(source: move.source, destination: target))
        onRecord?(journal)
        return target
    }

    /// Macht einen Aufräumvorgang rückgängig. Leere, von Billy angelegte Ordner werden entfernt.
    public static func undo(_ journal: TidyJournal, fileManager: FileManager = .default) -> UndoResult {
        var result = UndoResult()
        for record in journal.records.reversed() {
            guard fileManager.fileExists(atPath: record.destination.path) else {
                result.failed.append(record.destination.lastPathComponent)
                continue
            }
            let folder = record.source.deletingLastPathComponent()
            let target = UniqueNamer.uniqueURL(in: folder, fileName: record.source.lastPathComponent) {
                fileManager.fileExists(atPath: $0.path)
            }
            do {
                try fileManager.moveItem(at: record.destination, to: target)
                result.restored += 1
            } catch {
                result.failed.append(record.destination.lastPathComponent)
            }
        }
        for folder in journal.createdFolders.reversed() {
            let contents = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? ["?"]
            let remaining = contents.filter { $0 != ".DS_Store" }
            if remaining.isEmpty {
                try? fileManager.removeItem(at: folder)
            }
        }
        return result
    }
}

/// Speichert das letzte Aufräum-Journal als JSON.
public struct JournalStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func save(_ journal: TidyJournal) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(journal).write(to: url, options: .atomic)
    }

    public func load() -> TidyJournal? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TidyJournal.self, from: data)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
