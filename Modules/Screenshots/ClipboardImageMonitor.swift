import AppKit
import CryptoKit

@MainActor
final class ClipboardImageMonitor {

    static let selfWriteMarker = NSPasteboard.PasteboardType("com.lincode.PersonalIsland.self-write")

    private static let pollInterval: TimeInterval = 0.5

    private let buffer: ScreenshotBuffer
    private var timer: Timer?

    private var lastChangeCount = NSPasteboard.general.changeCount

    init(buffer: ScreenshotBuffer) {
        self.buffer = buffer
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Log.clipboard.info("Clipboard monitor started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        Log.clipboard.info("Clipboard monitor stopped")
    }

    private func tick() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        guard pasteboard.types?.contains(Self.selfWriteMarker) != true else { return }

        guard pasteboard.availableType(from: [.png, .tiff]) != nil else { return }

        let pngData = pasteboard.data(forType: .png)
        guard let raw = pngData ?? pasteboard.data(forType: .tiff) else { return }
        ingest(raw: raw, isPNG: pngData != nil)
    }

    private func ingest(raw: Data, isPNG: Bool) {
        let buffer = self.buffer
        let cacheDir = ScreenshotCache.directory
        Task.detached(priority: .utility) {
            let png: Data
            if isPNG {
                png = raw
            } else {
                guard let rep = NSBitmapImageRep(data: raw),
                      let converted = rep.representation(using: .png, properties: [:])
                else { return }
                png = converted
            }
            let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
            if await buffer.containsHash(hash) { return }

            let url = cacheDir.appendingPathComponent(Self.cacheFileName(for: Date()))
            do {
                try png.write(to: url)
            } catch {
                Log.clipboard.error("Cache write failed: \(error.localizedDescription)")
                return
            }
            let thumbnail = ScreenshotThumbnailService.downscale(data: png)

            await MainActor.run {
                let item = ScreenshotItem(
                    source: .clipboard,
                    creationDate: Date(),
                    cacheURL: url,
                    pngHash: hash,
                    thumbnail: thumbnail
                )
                if buffer.insert(item) {
                    Log.clipboard.info("Ingested clipboard image (\(png.count) bytes)")
                }
            }
        }
    }

    private nonisolated static func cacheFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return "Screenshot-\(formatter.string(from: date)).png"
    }

    static func copyToPasteboard(_ items: [ScreenshotItem]) {
        let pasteboardItems: [NSPasteboardItem] = items.compactMap { item in
            guard let url = item.fileURL else { return nil }
            let pbItem = NSPasteboardItem()
            if let png = try? Data(contentsOf: url) {
                pbItem.setData(png, forType: .png)
            }
            pbItem.setString(url.absoluteString, forType: .fileURL)
            pbItem.setData(Data(), forType: selfWriteMarker)
            return pbItem
        }
        guard !pasteboardItems.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(pasteboardItems)
        Log.clipboard.info("Copied \(pasteboardItems.count) item(s) to clipboard")
    }
}
