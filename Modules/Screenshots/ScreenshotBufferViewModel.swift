import AppKit
import Combine
import SwiftUI

@MainActor
final class ScreenshotsModuleController {
    static let shared = ScreenshotsModuleController()

    let buffer: ScreenshotBuffer
    let viewModel: ScreenshotBufferViewModel
    private let clipboardMonitor: ClipboardImageMonitor
    private let directoryMonitor: ScreenshotDirectoryMonitor
    private var isActive = false

    private init() {
        let buffer = ScreenshotBuffer()
        self.buffer = buffer
        viewModel = ScreenshotBufferViewModel(buffer: buffer)
        clipboardMonitor = ClipboardImageMonitor(buffer: buffer)
        directoryMonitor = ScreenshotDirectoryMonitor(buffer: buffer, appStart: Date())
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        ScreenshotCache.purgeStaleFiles()
        clipboardMonitor.start()
        directoryMonitor.start()
        Log.screenshots.info("Screenshots module activated")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        clipboardMonitor.stop()
        directoryMonitor.stop()
    }
}

@MainActor
final class ScreenshotBufferViewModel: ObservableObject {
    @Published var selectedIDs: Set<UUID> = []
    @Published var previewItem: ScreenshotItem?
    @Published var quickLookURL: URL?

    let buffer: ScreenshotBuffer
    private var cancellable: AnyCancellable?

    init(buffer: ScreenshotBuffer) {
        self.buffer = buffer

        cancellable = buffer.$items.sink { [weak self] items in
            guard let self else { return }
            let ids = Set(items.map(\.id))
            selectedIDs.formIntersection(ids)
            if let preview = previewItem, !ids.contains(preview.id) {
                previewItem = nil
            }
        }
    }

    func isSelected(_ item: ScreenshotItem) -> Bool {
        selectedIDs.contains(item.id)
    }

    var selectedItems: [ScreenshotItem] {
        buffer.items.filter { selectedIDs.contains($0.id) }
    }

    private var pendingPreviewTask: Task<Void, Never>?

    func handleClick(_ item: ScreenshotItem, commandKey: Bool) {
        if commandKey {
            if selectedIDs.contains(item.id) {
                selectedIDs.remove(item.id)
            } else {
                selectedIDs.insert(item.id)
            }
            return
        }
        if selectedIDs.contains(item.id) {
            pendingPreviewTask?.cancel()
            pendingPreviewTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
                guard !Task.isCancelled else { return }
                self?.previewItem = item
            }
        } else {
            selectedIDs = [item.id]
        }
    }

    func handleDoubleClick(_ item: ScreenshotItem) {
        pendingPreviewTask?.cancel()
        pendingPreviewTask = nil
        open(item)
    }

    func dragPayload(for item: ScreenshotItem) -> [ScreenshotItem] {
        let resolution = ScreenshotDragPayloadBuilder.resolve(
            draggedItem: item,
            selectedIDs: selectedIDs,
            bufferItems: buffer.items
        )
        if resolution.newSelection != selectedIDs {
            selectedIDs = resolution.newSelection
        }
        return resolution.payload
    }

    func copySelected() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        ClipboardImageMonitor.copyToPasteboard(items)
    }

    func copy(_ item: ScreenshotItem) {
        ClipboardImageMonitor.copyToPasteboard([item])
    }

    func removeSelected() {
        guard !selectedIDs.isEmpty else { return }
        buffer.remove(ids: selectedIDs)
        selectedIDs.removeAll()
    }

    func remove(_ item: ScreenshotItem) {
        buffer.remove(id: item.id)
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func open(_ item: ScreenshotItem) {
        guard let url = item.fileURL else { return }
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ item: ScreenshotItem) {
        guard let url = item.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func showQuickLook(_ item: ScreenshotItem) {
        quickLookURL = item.fileURL
    }

    func closePreview() {
        previewItem = nil
    }
}
