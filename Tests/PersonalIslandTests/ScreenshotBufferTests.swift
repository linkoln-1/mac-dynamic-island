import XCTest
@testable import PersonalIsland

private final class SpyFileRemover: ScreenshotFileRemoving {
    private(set) var removedURLs: [URL] = []
    func removeFile(at url: URL) { removedURLs.append(url) }
}

@MainActor
final class ScreenshotBufferTests: XCTestCase {
    private var spy = SpyFileRemover()

    override func setUp() {
        super.setUp()
        spy = SpyFileRemover()
    }

    private func makeBuffer(maxItems: Int = ScreenshotBufferSettings.maxItems) -> ScreenshotBuffer {
        ScreenshotBuffer(maxItems: maxItems, fileRemover: spy)
    }

    private func diskItem(path: String, date: Date = Date(), pinned: Bool = false) -> ScreenshotItem {
        ScreenshotItem(
            source: .screenshotFile,
            originalURL: URL(fileURLWithPath: path),
            creationDate: date,
            isPinned: pinned
        )
    }

    private func clipboardItem(hash: String, cachePath: String, date: Date = Date()) -> ScreenshotItem {
        ScreenshotItem(
            source: .clipboard,
            creationDate: date,
            cacheURL: URL(fileURLWithPath: cachePath),
            pngHash: hash
        )
    }

    func testBufferStartsEmptyWithConfiguredLimit() {
        let buffer = ScreenshotBuffer()
        XCTAssertTrue(buffer.items.isEmpty)
        XCTAssertEqual(buffer.maxItems, ScreenshotBufferSettings.maxItems)
        XCTAssertEqual(buffer.maxItems, 30)
    }

    func testInsertRejectsDuplicateHash() {
        let buffer = makeBuffer()
        XCTAssertTrue(buffer.insert(clipboardItem(hash: "abc", cachePath: "/tmp/a.png")))
        XCTAssertFalse(buffer.insert(clipboardItem(hash: "abc", cachePath: "/tmp/b.png")))
        XCTAssertEqual(buffer.items.count, 1)
        XCTAssertTrue(buffer.containsHash("abc"))
        XCTAssertFalse(buffer.containsHash("zzz"))
    }

    func testInsertRejectsDuplicatePath() {
        let buffer = makeBuffer()
        XCTAssertTrue(buffer.insert(diskItem(path: "/Users/me/Desktop/shot.png")))
        XCTAssertFalse(buffer.insert(diskItem(path: "/Users/me/Desktop/shot.png")))
        XCTAssertEqual(buffer.items.count, 1)
        XCTAssertTrue(buffer.containsPath("/Users/me/Desktop/shot.png"))
    }

    func testSameContentCanReturnAfterRemoval() {
        let buffer = makeBuffer()
        let item = clipboardItem(hash: "abc", cachePath: "/tmp/a.png")
        buffer.insert(item)
        buffer.remove(id: item.id)
        XCTAssertTrue(buffer.insert(clipboardItem(hash: "abc", cachePath: "/tmp/a2.png")))
    }

    func testItemsAreNewestFirst() {
        let buffer = makeBuffer()
        let first = diskItem(path: "/d/1.png")
        let second = diskItem(path: "/d/2.png")
        let third = diskItem(path: "/d/3.png")
        buffer.insert(first)
        buffer.insert(second)
        buffer.insert(third)
        XCTAssertEqual(buffer.items.map(\.id), [third.id, second.id, first.id])
    }

    func testEvictionRemovesOldestBeyondLimit() {
        let buffer = makeBuffer(maxItems: 3)
        let oldest = diskItem(path: "/d/1.png")
        buffer.insert(oldest)
        buffer.insert(diskItem(path: "/d/2.png"))
        buffer.insert(diskItem(path: "/d/3.png"))
        let newest = diskItem(path: "/d/4.png")
        buffer.insert(newest)

        XCTAssertEqual(buffer.items.count, 3)
        XCTAssertFalse(buffer.items.contains { $0.id == oldest.id })
        XCTAssertEqual(buffer.items.first?.id, newest.id)
        XCTAssertFalse(buffer.containsPath("/d/1.png"), "evicted path must be reusable")
    }

    func testEvictionSkipsPinnedItems() {
        let buffer = makeBuffer(maxItems: 2)
        let pinnedOldest = diskItem(path: "/d/pin.png", pinned: true)
        let unpinned = diskItem(path: "/d/2.png")
        buffer.insert(pinnedOldest)
        buffer.insert(unpinned)
        buffer.insert(diskItem(path: "/d/3.png"))

        XCTAssertEqual(buffer.items.count, 2)
        XCTAssertTrue(buffer.items.contains { $0.id == pinnedOldest.id })
        XCTAssertFalse(buffer.items.contains { $0.id == unpinned.id })
    }

    func testRemovalOfDiskItemNeverInvokesFileOperations() {
        let buffer = makeBuffer()
        let item = diskItem(path: "/Users/me/Desktop/shot.png")
        buffer.insert(item)
        buffer.remove(id: item.id)

        XCTAssertTrue(buffer.items.isEmpty)
        XCTAssertTrue(spy.removedURLs.isEmpty, "disk originals must NEVER be deleted")
    }

    func testEvictionOfDiskItemNeverInvokesFileOperations() {
        let buffer = makeBuffer(maxItems: 1)
        buffer.insert(diskItem(path: "/d/1.png"))
        buffer.insert(diskItem(path: "/d/2.png"))

        XCTAssertEqual(buffer.items.count, 1)
        XCTAssertTrue(spy.removedURLs.isEmpty, "evicting disk items must not delete files")
    }

    func testRemovalOfClipboardItemDeletesOnlyOwnCacheCopy() {
        let buffer = makeBuffer()
        let disk = diskItem(path: "/Users/me/Desktop/shot.png")
        let clip = clipboardItem(hash: "h1", cachePath: "/tmp/cache/clip.png")
        buffer.insert(disk)
        buffer.insert(clip)
        buffer.remove(ids: [disk.id, clip.id])

        XCTAssertTrue(buffer.items.isEmpty)
        XCTAssertEqual(spy.removedURLs, [URL(fileURLWithPath: "/tmp/cache/clip.png")])
    }

    func testLocationResolutionExpandsTilde() {
        let home = URL(fileURLWithPath: "/Users/testuser")
        let resolved = ScreenshotLocationResolver.resolveSaveDirectory(
            preferenceValue: "~/Documents/", homeDirectory: home
        )
        XCTAssertEqual(resolved.standardizedFileURL.path, "/Users/testuser/Documents")
    }

    func testLocationResolutionBareTildeIsHome() {
        let home = URL(fileURLWithPath: "/Users/testuser")
        let resolved = ScreenshotLocationResolver.resolveSaveDirectory(
            preferenceValue: "~", homeDirectory: home
        )
        XCTAssertEqual(resolved.standardizedFileURL.path, "/Users/testuser")
    }

    func testLocationResolutionMissingKeyFallsBackToDesktop() {
        let home = URL(fileURLWithPath: "/Users/testuser")
        for missing in [nil, "", "   "] {
            let resolved = ScreenshotLocationResolver.resolveSaveDirectory(
                preferenceValue: missing, homeDirectory: home
            )
            XCTAssertEqual(resolved.standardizedFileURL.path, "/Users/testuser/Desktop")
        }
    }

    func testLocationResolutionKeepsAbsolutePath() {
        let home = URL(fileURLWithPath: "/Users/testuser")
        let resolved = ScreenshotLocationResolver.resolveSaveDirectory(
            preferenceValue: "/Custom/Shots", homeDirectory: home
        )
        XCTAssertEqual(resolved.standardizedFileURL.path, "/Custom/Shots")
    }
}
