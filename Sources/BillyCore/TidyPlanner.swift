import Foundation

/// Ein Eintrag auf dem Schreibtisch.
public struct DesktopItem: Equatable, Sendable {
    public let url: URL
    public let isDirectory: Bool

    public init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }
}

/// Eine geplante Verschiebung.
public struct TidyMove: Codable, Equatable, Sendable {
    public let source: URL
    public let destination: URL
    public let category: DesktopCategory

    public init(source: URL, destination: URL, category: DesktopCategory) {
        self.source = source
        self.destination = destination
        self.category = category
    }

    public var folder: URL { destination.deletingLastPathComponent() }
}

/// Ergebnis der Planung: welche Datei in welchen Ordner wandert.
public struct TidyPlan: Equatable, Sendable {
    public let moves: [TidyMove]

    public var isEmpty: Bool { moves.isEmpty }

    /// Anzahl je Kategorie in fester Reihenfolge.
    public var counts: [(category: DesktopCategory, count: Int)] {
        DesktopCategory.allCases.compactMap { category in
            let n = moves.filter { $0.category == category }.count
            return n > 0 ? (category, n) : nil
        }
    }

    /// Benötigte Zielordner in fester Reihenfolge.
    public var folders: [URL] {
        var seen = Set<URL>()
        return moves.map(\.folder).filter { seen.insert($0).inserted }
    }

    /// Menschlich lesbare Zusammenfassung, z. B. „12 × Screenshots“.
    public var summaryLines: [String] {
        counts.map { "\($0.count) × \($0.category.folderName)" }
    }
}

public enum TidyPlanner {
    /// Endungen von Dateien, die gerade noch geladen werden.
    static let inProgressExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload"]

    /// Plant das Aufräumen. Ordner (inkl. Apps/Pakete) und versteckte Dateien bleiben liegen,
    /// es wird nie etwas überschrieben oder gelöscht.
    public static func plan(items: [DesktopItem], desktop: URL, fileExists: (URL) -> Bool) -> TidyPlan {
        var reserved = Set<String>()
        var moves: [TidyMove] = []
        let sorted = items.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        for item in sorted {
            let name = item.url.lastPathComponent
            guard shouldMove(name: name, isDirectory: item.isDirectory) else { continue }
            let category = FileCategorizer.category(forFileName: name)
            let folder = desktop.appendingPathComponent(category.folderName, isDirectory: true)
            let destination = UniqueNamer.uniqueURL(in: folder, fileName: name) { url in
                reserved.contains(url.path) || fileExists(url)
            }
            reserved.insert(destination.path)
            moves.append(TidyMove(source: item.url, destination: destination, category: category))
        }
        return TidyPlan(moves: moves)
    }

    static func shouldMove(name: String, isDirectory: Bool) -> Bool {
        if isDirectory { return false }
        if name.hasPrefix(".") || name.hasPrefix("Icon\r") { return false }
        let ext = (name.lowercased() as NSString).pathExtension
        return !inProgressExtensions.contains(ext)
    }
}

/// Findet freie Dateinamen nach Finder-Art: „Bild.png“ → „Bild 2.png“.
public enum UniqueNamer {
    public static func candidate(for fileName: String, attempt: Int) -> String {
        guard attempt > 1 else { return fileName }
        let ns = fileName as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        return ext.isEmpty ? "\(base) \(attempt)" : "\(base) \(attempt).\(ext)"
    }

    public static func uniqueURL(in folder: URL, fileName: String, isTaken: (URL) -> Bool) -> URL {
        var attempt = 1
        while true {
            let url = folder.appendingPathComponent(candidate(for: fileName, attempt: attempt))
            if !isTaken(url) { return url }
            attempt += 1
        }
    }
}
