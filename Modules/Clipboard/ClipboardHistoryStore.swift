import AppKit
import Combine
import Foundation

protocol ClipboardWriting {
    func write(_ string: String)
}

struct MarkedSystemClipboardWriter: ClipboardWriting {
    func write(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, ClipboardImageMonitor.selfWriteMarker], owner: nil)
        pasteboard.setString(string, forType: .string)
        pasteboard.setString("1", forType: ClipboardImageMonitor.selfWriteMarker)
    }
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let maxEntries = 50

    @Published private(set) var entries: [ClipboardEntry] = []

    private let now: () -> Date
    private let writer: ClipboardWriting

    init(now: @escaping () -> Date = Date.init, writer: ClipboardWriting = MarkedSystemClipboardWriter()) {
        self.now = now
        self.writer = writer
    }

    func ingest(_ string: String) {
        guard let entry = ClipboardClassifier.entry(from: string, at: now()) else { return }
        insert(entry)
    }

    func ingestFile(path: String) {
        insert(ClipboardClassifier.fileEntry(path: path, at: now()))
    }

    private func insert(_ entry: ClipboardEntry) {
        if let index = entries.firstIndex(where: { $0.contentHash == entry.contentHash }) {
            var existing = entries.remove(at: index)
            existing.createdAt = now()
            entries.insert(existing, at: 0)
            resort()
            return
        }
        entries.insert(entry, at: 0)
        resort()
        evictOverflow()
    }

    func copyToPasteboard(_ id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        writer.write(entry.content)
    }

    func togglePin(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isPinned.toggle()
        resort()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    func clearUnpinned() {
        entries.removeAll { !$0.isPinned }
    }

    func filtered(kind: ClipboardEntryKind?) -> [ClipboardEntry] {
        guard let kind else { return entries }
        return entries.filter { $0.kind == kind }
    }

    func count(kind: ClipboardEntryKind) -> Int {
        entries.filter { $0.kind == kind }.count
    }

    private func resort() {
        entries.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func evictOverflow() {
        while entries.count > Self.maxEntries {
            guard let index = entries.lastIndex(where: { !$0.isPinned }) else { return }
            entries.remove(at: index)
        }
    }
}

@MainActor
final class ClipboardModuleController {
    static let shared = ClipboardModuleController()

    let store: ClipboardHistoryStore
    private let monitor: ClipboardHistoryMonitor

    private init() {
        let store = ClipboardHistoryStore()
        self.store = store
        monitor = ClipboardHistoryMonitor(store: store)
    }

    func activate() {
        monitor.start()
    }

    func deactivate() {
        monitor.stop()
    }
}
