import AppKit
import Foundation

struct ScreenshotItem: Identifiable, Equatable {
    enum Source: Equatable {
        case clipboard
        case screenshotFile
    }

    let id: UUID
    var source: Source

    var originalURL: URL?
    var creationDate: Date

    var isPinned: Bool

    var cacheURL: URL?

    var pngHash: String?

    var thumbnail: NSImage?

    init(
        id: UUID = UUID(),
        source: Source = .clipboard,
        originalURL: URL? = nil,
        creationDate: Date = Date(),
        isPinned: Bool = false,
        cacheURL: URL? = nil,
        pngHash: String? = nil,
        thumbnail: NSImage? = nil
    ) {
        self.id = id
        self.source = source
        self.originalURL = originalURL
        self.creationDate = creationDate
        self.isPinned = isPinned
        self.cacheURL = cacheURL
        self.pngHash = pngHash
        self.thumbnail = thumbnail
    }

    var fileURL: URL? { originalURL ?? cacheURL }

    var fileExists: Bool {
        guard let url = fileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.isPinned == rhs.isPinned
            && lhs.thumbnail === rhs.thumbnail
    }
}
