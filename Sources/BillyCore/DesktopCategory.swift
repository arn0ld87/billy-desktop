import Foundation

/// Zielordner, in die Billy Dateien vom Schreibtisch trägt.
public enum DesktopCategory: String, CaseIterable, Codable, Sendable {
    case screenshots
    case images
    case documents
    case music
    case videos
    case archives
    case installers
    case code
    case other

    /// Ordnername auf dem Schreibtisch.
    public var folderName: String {
        switch self {
        case .screenshots: return "Screenshots"
        case .images: return "Bilder"
        case .documents: return "Dokumente"
        case .music: return "Musik"
        case .videos: return "Videos"
        case .archives: return "Archive"
        case .installers: return "Installer"
        case .code: return "Code"
        case .other: return "Sonstiges"
        }
    }
}

/// Ordnet einen Dateinamen einer Kategorie zu (nur anhand von Name und Endung).
public enum FileCategorizer {
    static let screenshotPrefixes = [
        "bildschirmfoto", "bildschirmaufnahme", "screenshot", "screen shot",
        "screen recording", "cleanshot",
    ]

    static let extensions: [DesktopCategory: Set<String>] = [
        .images: ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp",
                  "svg", "raw", "cr2", "cr3", "nef", "arw", "dng", "psd", "ai", "sketch", "fig", "avif"],
        .documents: ["pdf", "doc", "docx", "pages", "odt", "rtf", "rtfd", "txt", "md", "tex",
                     "xls", "xlsx", "numbers", "ods", "csv", "ppt", "pptx", "key", "odp", "epub"],
        .music: ["mp3", "wav", "aiff", "aif", "m4a", "flac", "ogg", "aac", "opus", "mid", "midi"],
        .videos: ["mov", "mp4", "m4v", "avi", "mkv", "webm", "wmv", "mpg", "mpeg"],
        .archives: ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst"],
        .installers: ["dmg", "pkg", "mpkg", "iso"],
        .code: ["swift", "py", "js", "ts", "tsx", "jsx", "html", "css", "json", "yaml", "yml",
                "toml", "sh", "zsh", "c", "cpp", "h", "hpp", "m", "java", "kt", "rb", "go",
                "rs", "php", "sql", "xml", "ipynb"],
    ]

    public static func category(forFileName name: String) -> DesktopCategory {
        let lower = name.lowercased()
        let ext = (lower as NSString).pathExtension
        let isMedia = extensions[.images]!.contains(ext) || extensions[.videos]!.contains(ext)
        if isMedia, screenshotPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return .screenshots
        }
        for category in DesktopCategory.allCases {
            if let exts = extensions[category], exts.contains(ext) {
                return category
            }
        }
        return .other
    }
}
