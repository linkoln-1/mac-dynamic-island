# Research: screenshots

## Recommendation
Primary disk detection: NSMetadataQuery (Spotlight) with predicate "kMDItemIsScreenCapture == 1 AND kMDItemFSCreationDate > appStart", scope NSMetadataQueryUserHomeScope, run on the main runloop — verified live on this machine (initial gather 1.0s, new capture surfaced as NSMetadataQueryDidUpdate ~7.6s after file creation; date-filtered gather correctly returned 0 pre-existing items). Do NOT build the com.apple.screencapture-location + DispatchSource watcher as primary — on this machine `location` does not exist AND `target = clipboard`, so ⌘⇧3/4 go to the clipboard, not disk; the folder-watch approach would watch the wrong thing. Clipboard ingestion is therefore co-primary: poll NSPasteboard.general.changeCount every 0.5s, read `public.png` (verified present, 729KB vs 43.7MB TIFF), dedup via changeCount + SHA-256, and suppress self-writes with a private marker pasteboard type (verified working). Normalize every item to a real file URL at ingest (clipboard PNGs written to a cache dir off-main) — then drag-out is just SwiftUI `.onDrag { NSItemProvider(contentsOf: url)! }`, preview is a custom in-island large preview (with optional one-line `.quickLookPreview($url)`, which typechecks on this SDK), thumbnails come from QLThumbnailGenerator for files (65.7ms measured) and CGImageSourceCreateThumbnailAtIndex for clipboard data (37.6ms, ~413KB per 400px thumb, ~12MB for 30).

## Implementation notes
VERIFIED LOCAL FACTS (macOS 26.6.2, Swift 6.3.3, this machine)
- `defaults read com.apple.screencapture location` → does not exist. `target = clipboard` (user's ⌘⇧3/4 currently go to CLIPBOARD, not disk). `location-last = "~/Documents/"` (tilde form — must expandingTildeInPath). Fallback dir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask) == ~/Desktop == NSHomeDirectory()+"/Desktop" here (no sandbox, so they agree).
- `screencapture -x file.png` output receives kMDItemIsScreenCapture = 1 within ~2s (Spotlight indexing lag; mdls returns null immediately after creation).
- NSMetadataQuery live test: predicate `kMDItemIsScreenCapture == 1`, scope UserHomeScope, started on main runloop → DidFinishGathering at 1.0s (13 pre-existing results), DidUpdate with the new file 7.6s after capture. Compound predicate `... AND kMDItemFSCreationDate > %@` (appStart as NSDate) → initial resultCount 0, new capture still detected. This is the "only new items" filter — put the date in the PREDICATE, not post-filtering.
- Clipboard after `screencapture -c`: types = [public.png, Apple PNG pasteboard type, public.tiff, NeXT TIFF v4.0]. PNG data 729,439 B; TIFF 43,722,694 B (60x). Always read .png first, .tiff only as fallback; never retain TIFF bytes.
- changeCount increments on every write including our own; writing a custom marker type (`NSPasteboard.PasteboardType("com.<you>.screenshotbuffer.self-write")`) alongside image data survives and is visible via pb.types.contains(marker).
- API typecheck pass on this SDK: .quickLookPreview($url), .onDrag { NSItemProvider(contentsOf:)! }, QLThumbnailGenerator.Request(fileAt:size:scale:representationTypes:), CGImageSourceCreateThumbnailAtIndex opts, QLPreviewPanel.shared(), NSWorkspace.shared.open / activateFileViewerSelecting.
- Perf: CGImageSource 400px thumb of 2056×1329 PNG = 37.6ms, output 400×258 ≈ 413KB RGBA. QLThumbnailGenerator same file = 65.7ms.

MODULE DESIGN
Model: ScreenshotItem { id: UUID, fileURL: URL (ALWAYS set — see normalization), source: .disk | .clipboard, createdAt: Date, thumbnail: NSImage?, pngHash: String? }. Store: @MainActor final class ScreenshotBufferStore: ObservableObject { @Published var items: [ScreenshotItem] } capped at 30, evict oldest (delete its cache file if source == .clipboard).

1) DISK WATCHER (NSMetadataQuery, main thread)
- Create on main. predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemFSCreationDate > %@", appStart as NSDate). searchScopes = [NSMetadataQueryUserHomeScope]. notificationBatchingInterval = 0.2 (default 1.0). sortDescriptors optional.
- Observe on NotificationCenter with object: query, queue: .main → names: .NSMetadataQueryDidStartGathering, .NSMetadataQueryGatheringProgress, .NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate.
- query.start() MUST be called on a thread with a running runloop (main). Alternatively set query.operationQueue = OperationQueue.main before start.
- On DidFinishGathering: query.disableUpdates(); enumerate query.results (should be 0 thanks to date predicate, but harvest anyway); query.enableUpdates(). Live updates flow only after gathering completes.
- On DidUpdate: read userInfo[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] (also ChangedItemsKey — a screenshot occasionally appears there after rename). Extract path via item.value(forAttribute: NSMetadataItemPathKey) as? String, creation date via NSMetadataItemFSCreationDateKey.
- Dedup: keep Set<String> of ingested paths; skip dupes and skip paths inside your own cache dir.
- Why not folder watching as primary: location default may not exist (verified), user can point it anywhere anytime, target may be clipboard (verified it IS here), and kMDItemIsScreenCapture catches screenshots regardless of folder incl. third-party tools that set it. Optional latency supplement: DispatchSource.makeFileSystemObjectSource(fileDescriptor: open(dir, O_EVTONLY), eventMask: .write, queue: bg) on the resolved dir (read UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") ?? "~/Desktop", expand tilde) to pick up files 2–8s sooner; dedup by path makes double-reporting harmless. Ship v1 without it.

2) CLIPBOARD WATCHER (main thread Timer)
- Timer.scheduledTimer 0.5s, add to RunLoop.main in .common mode (keeps firing during menu/drag tracking). 0.5s is standard (clipboard managers use 0.5–1s); the check is just an int compare — negligible cost.
- Tick: let cc = pb.changeCount; guard cc != lastChangeCount else return; lastChangeCount = cc.
- Skip self-writes: if pb.types?.contains(selfMarker) == true → return (verified marker survives).
- Guard content: guard pb.availableType(from: [.png, .tiff]) != nil else return. Note: a Finder file-copy exposes .fileURL, not raw .png data, so ordinary file copies are ignored automatically.
- Read data = pb.data(forType: .png) ?? pb.data(forType: .tiff) (convert TIFF→PNG via NSBitmapImageRep(data:)?.representation(using: .png, properties: [:]) on the bg queue before storing).
- Dedup: SHA-256 (import CryptoKit, SHA256.hash(data:)) of the PNG bytes; keep hashes of current buffer items; skip if seen. changeCount alone is not enough (apps re-write identical content).
- NORMALIZATION (do off-main, e.g. Task.detached(priority: .utility)): write PNG to cacheDir = ~/Library/Caches/<bundleID>/ClipboardShots/Screenshot-<yyyyMMdd-HHmmss-SSS>.png (FileManager.createDirectory withIntermediateDirectories once). Then every item has a real fileURL → one code path for drag/preview/open/reveal. Hop back to @MainActor to append the item.
- App's own Copy action: build ONE NSPasteboardItem carrying three types — setData(png, forType: .png), setString(url.absoluteString, forType: .fileURL), setData(Data(), forType: selfMarker) — then pb.clearContents(); pb.writeObjects([pbItem]); lastChangeCount = pb.changeCount (belt and suspenders on top of the marker). File URL + PNG together means Telegram/Slack attach the file and image editors paste pixels.

3) THUMBNAILS
- Disk items: QLThumbnailGenerator.shared.generateBestRepresentation(for: QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 200, height: 140), scale: 2.0, representationTypes: .thumbnail)) { rep, _ in ... rep?.nsImage ... } — completion arrives on an internal queue; hop to MainActor before mutating the store. 65.7ms measured; QL manages its own concurrency, no queue needed.
- Clipboard items (data already in RAM): CGImageSourceCreateWithData + CGImageSourceCreateThumbnailAtIndex with [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 400, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true] on the same detached utility task; wrap CGImage in NSImage. 37.6ms measured.
- Memory: 400px RGBA thumb ≈ 413KB → 30 items ≈ 12.4MB. Fine. NEVER retain full-size Data after the temp-file write + thumbnail are done; never retain the 43MB TIFF at all.

4) DRAG-OUT
- SwiftUI: .onDrag { NSItemProvider(contentsOf: item.fileURL)! } on the thumbnail view. NSItemProvider(contentsOf:) registers the file's UTType (public.png) + file URL; unsandboxed apps deliver a real file to Finder (copy), Telegram/Slack (attach), browsers (upload). The known "Sandbox extension data required for public.file-url" failure is sandbox-only — not applicable here. onDrag's closure runs synchronously at drag start; since items are pre-materialized to disk at ingest, no work is needed in the closure. Single-item drags only (known SwiftUI/Finder multi-file drop bug — irrelevant for one-thumbnail drags).
- Fallback if some target misbehaves (see risks): AppKit NSDraggingSource with NSFilePromiseProvider(fileType: UTType.png.identifier, delegate:) via an NSViewRepresentable mouseDown/beginDraggingSession — only build if needed.

5) PREVIEW
- Pragmatic primary: custom in-island large preview — on click/Space set store.previewItem; overlay a large Image(nsImage:) loaded via NSImage(contentsOf: fileURL) decoded off-main (or reuse CGImageSource with maxPixelSize 1600). Works regardless of window type (menu-bar island / non-activating NSPanel), no responder-chain requirements.
- One-line alternative (typechecks on this SDK): import QuickLook; .quickLookPreview($previewURL) with @State var previewURL: URL? — but QLPreviewPanel needs the app to be active and the window to become key; in a non-activating panel it can misbehave. Full QLPreviewPanel integration (override acceptsPreviewPanelControl/beginPreviewPanelControl/endPreviewPanelControl on an NSResponder in the chain, set panel.dataSource/delegate) is not worth it for this app.

6) OPEN / REVEAL
- Open in default app: NSWorkspace.shared.open(item.fileURL).
- Reveal in Finder: NSWorkspace.shared.activateFileViewerSelecting([item.fileURL]).
- Both work for clipboard items too because of normalization (the cache file IS the item).

THREADING SUMMARY
Main actor: store, NSMetadataQuery + its notifications, clipboard Timer tick (int compare + type check only), UI. Detached utility tasks: SHA-256, TIFF→PNG conversion, cache-file writes, CGImageSource downscale, full-size preview decode. QLThumbnailGenerator: its own queues, hop to @MainActor in the completion. No locks needed — all mutable state lives on the main actor; background work is pure functions Data→(hash, file, thumbnail) returning values.

PERMISSIONS: none required. No Screen Recording (the app never captures the screen), no Full Disk Access for ~/Desktop in an unsandboxed personal app. Spotlight must be enabled for the home volume (it is — verified).

LIFECYCLE: start both watchers at app launch; appStart = Date() captured before query.start(). query.stop() and timer.invalidate() on quit. Purge cacheDir entries older than N days at launch.

## Code sketch
import SwiftUI
import AppKit
import CryptoKit
import QuickLook
import QuickLookThumbnailing
import UniformTypeIdentifiers

// MARK: - Model
enum ShotSource { case disk, clipboard }

struct ScreenshotItem: Identifiable, Equatable {
    let id = UUID()
    let fileURL: URL          // always set: real screenshot file, or materialized clipboard PNG
    let source: ShotSource
    let createdAt: Date
    var thumbnail: NSImage?
    let pngHash: String?      // clipboard items only
    static func == (l: Self, r: Self) -> Bool { l.id == r.id }
}

// MARK: - Store
@MainActor
final class ScreenshotBufferStore: ObservableObject {
    static let maxItems = 30
    @Published private(set) var items: [ScreenshotItem] = []
    @Published var previewItem: ScreenshotItem?
    private var seenPaths = Set<String>()
    private var seenHashes = Set<String>()

    let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "ScreenshotBuffer", isDirectory: true)
            .appendingPathComponent("ClipboardShots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func containsPath(_ path: String) -> Bool { seenPaths.contains(path) }
    func containsHash(_ hash: String) -> Bool { seenHashes.contains(hash) }

    func insert(_ item: ScreenshotItem) {
        seenPaths.insert(item.fileURL.path)
        if let h = item.pngHash { seenHashes.insert(h) }
        items.insert(item, at: 0)
        while items.count > Self.maxItems {
            let evicted = items.removeLast()
            seenPaths.remove(evicted.fileURL.path)
            if let h = evicted.pngHash { seenHashes.remove(h) }
            if evicted.source == .clipboard { try? FileManager.default.removeItem(at: evicted.fileURL) }
        }
    }

    func setThumbnail(_ image: NSImage, for id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].thumbnail = image
    }
}

// MARK: - Disk watcher (NSMetadataQuery, main thread — needs a runloop)
@MainActor
final class DiskScreenshotWatcher {
    private let query = NSMetadataQuery()
    private let store: ScreenshotBufferStore
    private var observers: [NSObjectProtocol] = []

    init(store: ScreenshotBufferStore) { self.store = store }

    func start(appStart: Date) {
        query.predicate = NSPredicate(
            format: "kMDItemIsScreenCapture == 1 AND kMDItemFSCreationDate > %@",
            appStart as NSDate)                                   // verified: initial gather == 0
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.notificationBatchingInterval = 0.2

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .NSMetadataQueryDidFinishGathering,
                                        object: query, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.query.disableUpdates()
                self.harvest(self.query.results.compactMap { $0 as? NSMetadataItem })
                self.query.enableUpdates()                        // live updates start after gathering
            }
        })
        observers.append(nc.addObserver(forName: .NSMetadataQueryDidUpdate,
                                        object: query, queue: .main) { [weak self] note in
            let added = (note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem]) ?? []
            let changed = (note.userInfo?[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem]) ?? []
            guard let self else { return }
            MainActor.assumeIsolated { self.harvest(added + changed) }
        })
        query.start()                                             // main runloop — verified fires
    }

    func stop() { query.stop(); observers.forEach(NotificationCenter.default.removeObserver) }

    private func harvest(_ mdItems: [NSMetadataItem]) {
        for md in mdItems {
            guard let path = md.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !store.containsPath(path),
                  !path.hasPrefix(store.cacheDir.path) else { continue }
            let created = md.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date ?? Date()
            let item = ScreenshotItem(fileURL: URL(fileURLWithPath: path), source: .disk,
                                      createdAt: created, thumbnail: nil, pngHash: nil)
            store.insert(item)
            ThumbnailService.fileThumbnail(url: item.fileURL) { [weak store] img in
                if let img { store?.setThumbnail(img, for: item.id) }
            }
        }
    }
}

// MARK: - Clipboard watcher (0.5s changeCount poll)
@MainActor
final class ClipboardWatcher {
    static let selfMarker = NSPasteboard.PasteboardType("com.lincode.screenshotbuffer.self-write")
    private let store: ScreenshotBufferStore
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount   // baseline: ignore pre-launch clipboard

    init(store: ScreenshotBufferStore) { self.store = store }

    func start() {
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)                        // keeps firing during tracking
        timer = t
    }
    func stop() { timer?.invalidate() }

    private func tick() {
        let pb = NSPasteboard.general
        let cc = pb.changeCount
        guard cc != lastChangeCount else { return }
        lastChangeCount = cc
        guard pb.types?.contains(Self.selfMarker) != true else { return }   // our own ⌘C — verified
        guard pb.availableType(from: [.png, .tiff]) != nil else { return }  // Finder file-copies fail this
        guard let raw = pb.data(forType: .png) ?? pb.data(forType: .tiff) else { return }
        let isPNG = pb.data(forType: .png) != nil
        let cacheDir = store.cacheDir
        let store = self.store

        Task.detached(priority: .utility) {
            // TIFF fallback → PNG (screenshot clipboard has public.png; verified 729KB vs 43.7MB TIFF)
            let png: Data
            if isPNG { png = raw }
            else {
                guard let rep = NSBitmapImageRep(data: raw),
                      let converted = rep.representation(using: .png, properties: [:]) else { return }
                png = converted
            }
            let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
            if await store.containsHash(hash) { return }             // content dedup

            let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd-HHmmss-SSS"
            let url = cacheDir.appendingPathComponent("Screenshot-\(fmt.string(from: Date())).png")
            do { try png.write(to: url) } catch { return }           // normalize: every item is a file

            let thumb = ThumbnailService.downscale(data: png, maxPixel: 400)
            await MainActor.run {
                let item = ScreenshotItem(fileURL: url, source: .clipboard, createdAt: Date(),
                                          thumbnail: thumb, pngHash: hash)
                store.insert(item)
            }
        }
    }

    /// Copy action: file URL + PNG pixels + self-write marker in one pasteboard item.
    static func copyToPasteboard(_ item: ScreenshotItem) {
        let pb = NSPasteboard.general
        let pbItem = NSPasteboardItem()
        if let png = try? Data(contentsOf: item.fileURL) { pbItem.setData(png, forType: .png) }
        pbItem.setString(item.fileURL.absoluteString, forType: .fileURL)
        pbItem.setData(Data(), forType: selfMarker)
        pb.clearContents()
        pb.writeObjects([pbItem])
    }
}

// MARK: - Thumbnails
enum ThumbnailService {
    static func fileThumbnail(url: URL, completion: @MainActor @escaping (NSImage?) -> Void) {
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 200, height: 140),
                                               scale: 2.0, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            let img = rep?.nsImage                                   // 65.7ms measured
            Task { @MainActor in completion(img) }
        }
    }

    static func downscale(data: Data, maxPixel: Int) -> NSImage? {   // 37.6ms measured, ~413KB out
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

// MARK: - View: drag-out, copy, preview, open, reveal
struct ScreenshotCell: View {
    let item: ScreenshotItem
    @EnvironmentObject var store: ScreenshotBufferStore
    @State private var qlURL: URL?

    var body: some View {
        Group {
            if let t = item.thumbnail {
                Image(nsImage: t).resizable().scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(width: 100, height: 70)
        .onDrag { NSItemProvider(contentsOf: item.fileURL)! }        // real file to Finder/Telegram/Slack
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.fileURL) }
        .onTapGesture { store.previewItem = item }                   // in-island large preview overlay
        .contextMenu {
            Button("Copy") { ClipboardWatcher.copyToPasteboard(item) }
            Button("Quick Look") { qlURL = item.fileURL }            // optional system QL
            Button("Open") { NSWorkspace.shared.open(item.fileURL) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
            }
        }
        .quickLookPreview($qlURL)                                    // typechecks on this SDK
    }
}

// MARK: - Wiring (app launch)
// let store = ScreenshotBufferStore()
// let disk = DiskScreenshotWatcher(store: store); disk.start(appStart: Date())
// let clip = ClipboardWatcher(store: store); clip.start()

## Risks
1. Spotlight latency: NSMetadataQuery surfaced the new file 7.6s after creation in the live test (indexing lag ~2-8s; separate mdls poll showed the attribute appearing at ~2-4s). Additionally, with the Floating Thumbnail enabled, macOS only writes the screenshot file ~5s after capture. Total worst-case ~13s from keypress to buffer. Mitigation if it feels slow: add a supplemental DispatchSource.makeFileSystemObjectSource(.write) watcher on the resolved screencapture directory (UserDefaults suite "com.apple.screencapture" key "location", tilde-expanded, fallback ~/Desktop) — path-dedup makes double-reporting free. Clipboard path has none of this lag (≤0.5s).
2. THIS machine has target = clipboard: ⌘⇧3/4 currently produce NO disk file. Clipboard watching is not optional here — it is the main ingestion path. Also re-read the defaults if you ever display the "save location" (the `location` key can appear/disappear as the user changes Screenshot.app options; there is no change notification for another app's defaults — re-read lazily).
3. kMDItemIsScreenCapture was verified for `screencapture` CLI output; ⌘⇧3/4 use the same screencaptureui pipeline and are widely documented to set it (it powers Spotlight's "screenshot" search), but do one manual ⌘⇧5→"Save to Desktop" test on first run. If Spotlight indexing were ever disabled for the home volume, NSMetadataQuery goes silent — the DispatchSource supplement is the fallback.
4. Drag-out: NSItemProvider(contentsOf:) could not be verified headlessly. It is the standard unsandboxed path and the known failure ("Sandbox extension data required immediately for flavor public.file-url") is sandbox-specific; the other known bug (Finder rejecting MULTI-file drops from SwiftUI) doesn't apply to single-thumbnail drags. If a specific target app still rejects the drop, fall back to an NSViewRepresentable with NSDraggingSession + NSFilePromiseProvider (heavier, kept out of v1).
5. .quickLookPreview($url) requires the window to be able to become key; in a non-activating NSPanel/menu-bar island QLPreviewPanel may not appear or may steal focus — that is why the custom in-island preview is primary. Full QLPreviewPanel responder-chain integration is documented but not worth the complexity here.
6. TIFF memory spike: a clipboard screenshot's public.tiff was 43.7MB. Never read .tiff when .png exists; drop full-size Data references immediately after the cache write + thumbnail (both off-main) or 2-3 rapid screenshots can transiently hold >100MB.
7. changeCount polling misses nothing at 0.5s but a same-tick overwrite (clipboard replaced twice within 500ms) loses the first image — acceptable for screenshots. Timer must be in .common runloop mode or it stalls during menu tracking and drags.
8. Sequoia+ periodic screen-recording permission nags do NOT apply — this design never captures the screen and needs no TCC permission at all.
9. Cache growth: clipboard PNGs persist in ~/Library/Caches/<bundle>/ClipboardShots past the 30-item eviction only if the app crashes before eviction cleanup — purge stale files at launch.
10. Swift 6 concurrency: NSMetadataQuery and NSPasteboard are main-thread-ish (not Sendable); keep both watchers @MainActor and pass only value types (Data, URL, String) into detached tasks, as in the sketch, or strict concurrency checking will flag captures.

## Sources
- LOCAL: defaults read com.apple.screencapture — 'location' key absent, target=clipboard, location-last=~/Documents/ (macOS 26.6.2)
- LOCAL: mdls poll — kMDItemIsScreenCapture=1 appears ~2s after screencapture -x writes the file
- LOCAL: swift mdquery_test.swift — NSMetadataQuery UserHomeScope, gather 1.0s/13 results, DidUpdate +7.6s after capture, SUCCESS
- LOCAL: swift mdquery_date_test.swift — compound predicate kMDItemIsScreenCapture==1 AND kMDItemFSCreationDate>appStart: initial resultCount=0, live add detected, SUCCESS
- LOCAL: swift pb_test.swift — screencapture -c yields public.png 729KB + public.tiff 43.7MB; changeCount increments; custom self-write marker type visible after own write
- LOCAL: swiftc -typecheck api_check.swift — .quickLookPreview, .onDrag NSItemProvider(contentsOf:), QLThumbnailGenerator.Request, CGImageSource thumb opts, QLPreviewPanel, NSWorkspace APIs all compile on Swift 6.3.3 / macOS 26 SDK
- LOCAL: swift runtime_check.swift — UserDefaults(suiteName:'com.apple.screencapture') reads cross-domain; CGImageSource 400px thumb 37.6ms/413KB; QLThumbnailGenerator 65.7ms
- https://eclecticlight.co/2024/05/21/swiftui-on-macos-drag-and-drop-and-more/
- https://developer.apple.com/forums/thread/810749 (Finder multi-file drop limitation from SwiftUI)
- https://developer.apple.com/forums/thread/749094 (sandbox extension error for public.file-url — sandboxed apps only)
- https://swiftui-lab.com/drag-drop-with-swiftui/