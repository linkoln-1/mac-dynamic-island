import XCTest
@testable import PersonalIsland

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    private final class FakeReader: PasteboardReading {
        var changeCount = 0
        var typeIdentifiers: [String] = ["public.utf8-plain-text"]
        var string: String?
        var fileURLs: [URL] = []
        func readString() -> String? { string }
        func readFileURLs() -> [URL] { fileURLs }
    }

    private final class FakeWriter: ClipboardWriting {
        var written: [String] = []
        func write(_ string: String) { written.append(string) }
    }

    private var virtualNow = Date(timeIntervalSince1970: 500_000)
    private var store: ClipboardHistoryStore!
    private var writer: FakeWriter!
    private var reader: FakeReader!
    private var monitor: ClipboardHistoryMonitor!

    override func setUp() {
        virtualNow = Date(timeIntervalSince1970: 500_000)
        writer = FakeWriter()
        store = ClipboardHistoryStore(now: { self.virtualNow }, writer: writer)
        reader = FakeReader()
        monitor = ClipboardHistoryMonitor(store: store, reader: reader)
    }

    private func copyExternal(_ string: String, types: [String] = ["public.utf8-plain-text"]) {
        reader.changeCount += 1
        reader.typeIdentifiers = types
        reader.string = string
        reader.fileURLs = []
        monitor.poll()
    }

    func testClassification() {
        XCTAssertEqual(ClipboardClassifier.classify("hello world"), .text)
        XCTAssertEqual(ClipboardClassifier.classify("https://github.com/linkoln-1"), .url)
        XCTAssertEqual(ClipboardClassifier.classify("func main() {\n    print(1)\n}"), .code)
        XCTAssertEqual(ClipboardClassifier.classify("строка один\nстрока два"), .text)
        XCTAssertEqual(ClipboardClassifier.classify("see https://a.com and more\ntext"), .text)
    }

    func testEmptyAndOversizedSkipped() {
        XCTAssertNil(ClipboardClassifier.entry(from: "   \n  ", at: virtualNow))
        let huge = String(repeating: "a", count: ClipboardClassifier.maxContentLength + 1)
        XCTAssertNil(ClipboardClassifier.entry(from: huge, at: virtualNow))
    }

    func testMonitorCapturesTextAndFiles() {
        copyExternal("hello")
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].kind, .text)

        reader.changeCount += 1
        reader.fileURLs = [URL(fileURLWithPath: "/tmp/report.pdf")]
        monitor.poll()
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries[0].kind, .file)
        XCTAssertEqual(store.entries[0].preview, "report.pdf")
    }

    func testNoChangeCountNoIngest() {
        copyExternal("hello")
        reader.string = "another"
        monitor.poll()
        XCTAssertEqual(store.entries.count, 1)
    }

    func testConcealedAndSelfWriteSkipped() {
        copyExternal("secret-password", types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"])
        XCTAssertTrue(store.entries.isEmpty)

        copyExternal("transient", types: ["public.utf8-plain-text", "org.nspasteboard.TransientType"])
        XCTAssertTrue(store.entries.isEmpty)

        copyExternal("own write", types: [
            "public.utf8-plain-text", ClipboardImageMonitor.selfWriteMarker.rawValue,
        ])
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testDuplicateContentMovesToTopWithoutNewEntry() {
        copyExternal("first")
        virtualNow = virtualNow.addingTimeInterval(10)
        copyExternal("second")
        virtualNow = virtualNow.addingTimeInterval(10)
        copyExternal("first")

        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries[0].content, "first")
    }

    func testEvictionKeepsPinned() {
        copyExternal("keep me")
        store.togglePin(store.entries[0].id)
        for index in 0..<ClipboardHistoryStore.maxEntries {
            virtualNow = virtualNow.addingTimeInterval(1)
            copyExternal("entry \(index)")
        }
        XCTAssertEqual(store.entries.count, ClipboardHistoryStore.maxEntries)
        XCTAssertTrue(store.entries.contains { $0.content == "keep me" })
    }

    func testPinnedSortsFirst() {
        copyExternal("older")
        virtualNow = virtualNow.addingTimeInterval(10)
        copyExternal("newer")
        let olderID = store.entries.first { $0.content == "older" }!.id
        store.togglePin(olderID)
        XCTAssertEqual(store.entries[0].content, "older")
        store.togglePin(olderID)
        XCTAssertEqual(store.entries[0].content, "newer")
    }

    func testCopyWritesThroughMarkedWriter() {
        copyExternal("copy me")
        store.copyToPasteboard(store.entries[0].id)
        XCTAssertEqual(writer.written, ["copy me"])
    }

    func testRemoveAndClearUnpinned() {
        copyExternal("a")
        virtualNow = virtualNow.addingTimeInterval(1)
        copyExternal("b")
        store.togglePin(store.entries.first { $0.content == "a" }!.id)
        store.remove(store.entries.first { $0.content == "b" }!.id)
        XCTAssertEqual(store.entries.count, 1)

        virtualNow = virtualNow.addingTimeInterval(1)
        copyExternal("c")
        store.clearUnpinned()
        XCTAssertEqual(store.entries.map(\.content), ["a"])
    }

    func testFilterByKind() {
        copyExternal("plain")
        virtualNow = virtualNow.addingTimeInterval(1)
        copyExternal("https://example.com")
        XCTAssertEqual(store.filtered(kind: .url).count, 1)
        XCTAssertEqual(store.filtered(kind: .text).count, 1)
        XCTAssertEqual(store.filtered(kind: nil).count, 2)
        XCTAssertEqual(store.count(kind: .url), 1)
    }

    func testClipboardLocalizationKeys() {
        let suite = "clip-loc-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(AppLanguageMode.russian.rawValue, forKey: AppLanguageManager.defaultsKey)
        let ru = AppLanguageManager(defaults: defaults, preferredLanguages: { ["en"] })
        XCTAssertEqual(ru.string("module.clipboard.title"), "Буфер обмена")
        XCTAssertEqual(ru.string("clipboard.kind.url"), "Ссылка")
        XCTAssertEqual(ru.string("clipboard.action.pin"), "Закрепить")
        defaults.removePersistentDomain(forName: suite)
    }
}
