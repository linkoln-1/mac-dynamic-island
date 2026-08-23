import XCTest
@testable import PersonalIsland

final class ScreenshotDragPayloadBuilderTests: XCTestCase {

    private let itemA = ScreenshotItem(source: .screenshotFile, originalURL: URL(fileURLWithPath: "/tmp/a.png"))
    private let itemB = ScreenshotItem(source: .screenshotFile, originalURL: URL(fileURLWithPath: "/tmp/b.png"))
    private let itemC = ScreenshotItem(source: .clipboard, cacheURL: URL(fileURLWithPath: "/tmp/c.png"))
    private let itemD = ScreenshotItem(source: .clipboard, cacheURL: URL(fileURLWithPath: "/tmp/d.png"))
    private var buffer: [ScreenshotItem] { [itemA, itemB, itemC, itemD] }

    func testDraggingSelectedItemDragsWholeSelectionAndKeepsIt() {
        let selection: Set<UUID> = [itemA.id, itemB.id, itemC.id]
        let resolution = ScreenshotDragPayloadBuilder.resolve(
            draggedItem: itemB, selectedIDs: selection, bufferItems: buffer
        )
        XCTAssertEqual(resolution.payload.map(\.id), [itemA.id, itemB.id, itemC.id])
        XCTAssertEqual(resolution.newSelection, selection)
    }

    func testDraggingNonSelectedItemResetsSelectionToIt() {
        let selection: Set<UUID> = [itemA.id, itemB.id, itemC.id]
        let resolution = ScreenshotDragPayloadBuilder.resolve(
            draggedItem: itemD, selectedIDs: selection, bufferItems: buffer
        )
        XCTAssertEqual(resolution.payload.map(\.id), [itemD.id])
        XCTAssertEqual(resolution.newSelection, [itemD.id])
    }

    func testDraggingSoleSelectedItemDragsJustIt() {
        let resolution = ScreenshotDragPayloadBuilder.resolve(
            draggedItem: itemA, selectedIDs: [itemA.id], bufferItems: buffer
        )
        XCTAssertEqual(resolution.payload.map(\.id), [itemA.id])
        XCTAssertEqual(resolution.newSelection, [itemA.id])
    }

    func testDraggingWithEmptySelectionDragsJustTheItem() {
        let resolution = ScreenshotDragPayloadBuilder.resolve(
            draggedItem: itemD, selectedIDs: [], bufferItems: buffer
        )
        XCTAssertEqual(resolution.payload.map(\.id), [itemD.id])
        XCTAssertEqual(resolution.newSelection, [itemD.id])
    }

    func testPayloadOrderIsBufferOrderNotSelectionOrder() {

        let selection: Set<UUID> = [itemD.id, itemA.id, itemC.id]
        let resolution = ScreenshotDragPayloadBuilder.resolve(
            draggedItem: itemC, selectedIDs: selection, bufferItems: buffer
        )
        XCTAssertEqual(resolution.payload.map(\.id), [itemA.id, itemC.id, itemD.id])
    }

    func testFileURLsUseBackingFilesAndAreUniquePerItem() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("drag-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = dir.appendingPathComponent("original.png")
        let cacheOne = dir.appendingPathComponent("clip-1.png")
        let cacheTwo = dir.appendingPathComponent("clip-2.png")
        for url in [original, cacheOne, cacheTwo] {
            try Data([0x89, 0x50]).write(to: url)
        }

        let fileBacked = ScreenshotItem(source: .screenshotFile, originalURL: original)
        let clipOne = ScreenshotItem(source: .clipboard, cacheURL: cacheOne)
        let clipTwo = ScreenshotItem(source: .clipboard, cacheURL: cacheTwo)

        let urls = ScreenshotDragPayloadBuilder.fileURLs(for: [fileBacked, clipOne, clipTwo])

        XCTAssertEqual(urls, [original, cacheOne, cacheTwo])
        XCTAssertEqual(Set(urls).count, 3)
    }

    func testFileURLsSkipMissingFilesAndItemsWithoutURL() {
        let missing = ScreenshotItem(
            source: .screenshotFile,
            originalURL: URL(fileURLWithPath: "/tmp/definitely-missing-\(UUID().uuidString).png")
        )
        let urlless = ScreenshotItem(source: .clipboard)
        XCTAssertTrue(ScreenshotDragPayloadBuilder.fileURLs(for: [missing, urlless]).isEmpty)
    }
}
