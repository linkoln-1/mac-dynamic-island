import AppKit
import Foundation

enum ScreenshotLocationResolver {

    static func resolveSaveDirectory(
        preferenceValue: String?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let trimmed = preferenceValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return desktopFallback(homeDirectory: homeDirectory)
        }
        return expandTilde(trimmed, homeDirectory: homeDirectory)
    }

    static func currentSaveDirectory() -> URL {
        let value = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        return resolveSaveDirectory(preferenceValue: value)
    }

    private static func desktopFallback(homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent("Desktop", isDirectory: true)
    }

    private static func expandTilde(_ path: String, homeDirectory: URL) -> URL {
        if path == "~" {
            return homeDirectory
        }
        if path.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(path.dropFirst(2)), isDirectory: true)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

@MainActor
final class ScreenshotDirectoryMonitor {
    private let buffer: ScreenshotBuffer
    private let appStart: Date
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private var isStarted = false

    init(buffer: ScreenshotBuffer, appStart: Date = Date()) {
        self.buffer = buffer
        self.appStart = appStart
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        query.predicate = NSPredicate(
            format: "kMDItemIsScreenCapture == 1 AND kMDItemFSCreationDate > %@",
            appStart as NSDate
        )
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.notificationBatchingInterval = 0.2

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.query.disableUpdates()
                self.harvest(self.query.results.compactMap { $0 as? NSMetadataItem })
                self.query.enableUpdates()
            }
        })
        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: query, queue: .main
        ) { [weak self] note in

            let added = (note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem]) ?? []
            let changed = (note.userInfo?[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem]) ?? []
            guard let self else { return }
            MainActor.assumeIsolated { self.harvest(added + changed) }
        })

        query.start()
        Log.filesystem.info("Screenshot disk monitor started (Spotlight query)")
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        Log.filesystem.info("Screenshot disk monitor stopped")
    }

    private func harvest(_ mdItems: [NSMetadataItem]) {
        for mdItem in mdItems {
            guard let path = mdItem.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !buffer.containsPath(path),
                  !path.hasPrefix(ScreenshotCache.directory.path)
            else { continue }

            let created = mdItem.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date ?? Date()
            let item = ScreenshotItem(
                source: .screenshotFile,
                originalURL: URL(fileURLWithPath: path),
                creationDate: created
            )
            guard buffer.insert(item) else { continue }
            Log.filesystem.info("Ingested disk screenshot: \(path, privacy: .public)")

            let buffer = self.buffer
            ScreenshotThumbnailService.fileThumbnail(url: URL(fileURLWithPath: path)) { image in
                if let image { buffer.setThumbnail(image, for: item.id) }
            }
        }
    }
}
