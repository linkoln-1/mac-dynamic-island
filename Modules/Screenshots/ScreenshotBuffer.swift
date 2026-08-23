import AppKit
import Combine
import Foundation

protocol ScreenshotFileRemoving {
    func removeFile(at url: URL)
}

struct DefaultScreenshotFileRemover: ScreenshotFileRemoving {
    func removeFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Log.filesystem.error("Failed to remove cache file: \(error.localizedDescription)")
        }
    }
}

enum ScreenshotCache {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "PersonalIsland", isDirectory: true)
            .appendingPathComponent("ClipboardShots", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private static let stalePurgeAge: TimeInterval = 3 * 24 * 60 * 60

    static func purgeStaleFiles(now: Date = Date()) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        for url in urls {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if now.timeIntervalSince(created) > stalePurgeAge {
                try? fm.removeItem(at: url)
            }
        }
    }
}

@MainActor
final class ScreenshotBuffer: ObservableObject {
    @Published private(set) var items: [ScreenshotItem] = []

    let maxItems: Int
    private let fileRemover: ScreenshotFileRemoving

    init(
        maxItems: Int = ScreenshotBufferSettings.maxItems,
        fileRemover: ScreenshotFileRemoving = DefaultScreenshotFileRemover()
    ) {
        self.maxItems = maxItems
        self.fileRemover = fileRemover
    }

    func containsPath(_ path: String) -> Bool {
        items.contains { $0.originalURL?.path == path || $0.cacheURL?.path == path }
    }

    func containsHash(_ hash: String) -> Bool {
        items.contains { $0.pngHash == hash }
    }

    @discardableResult
    func insert(_ item: ScreenshotItem) -> Bool {
        if let hash = item.pngHash, containsHash(hash) {
            Log.screenshots.debug("Skipped duplicate by hash")
            return false
        }
        if let path = item.fileURL?.path, containsPath(path) {
            Log.screenshots.debug("Skipped duplicate by path")
            return false
        }
        items.insert(item, at: 0)
        evictOverflow()
        return true
    }

    func remove(ids: Set<UUID>) {
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        removed.forEach(deleteCacheCopyIfOwned)
    }

    func remove(id: UUID) {
        remove(ids: [id])
    }

    func setThumbnail(_ image: NSImage, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].thumbnail = image
    }

    func item(withID id: UUID) -> ScreenshotItem? {
        items.first { $0.id == id }
    }

    private func evictOverflow() {
        while items.count > maxItems {
            guard let index = items.lastIndex(where: { !$0.isPinned }) else { return }
            let evicted = items.remove(at: index)
            deleteCacheCopyIfOwned(evicted)
        }
    }

    private func deleteCacheCopyIfOwned(_ item: ScreenshotItem) {
        guard item.source == .clipboard, let cacheURL = item.cacheURL else { return }
        fileRemover.removeFile(at: cacheURL)
    }
}
