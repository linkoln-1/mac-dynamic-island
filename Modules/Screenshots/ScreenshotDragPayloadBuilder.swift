import Foundation

enum ScreenshotDragPayloadBuilder {
    struct Resolution: Equatable {

        let payload: [ScreenshotItem]

        let newSelection: Set<UUID>
    }

    static func resolve(
        draggedItem: ScreenshotItem,
        selectedIDs: Set<UUID>,
        bufferItems: [ScreenshotItem]
    ) -> Resolution {
        if selectedIDs.contains(draggedItem.id) {
            let payload = bufferItems.filter { selectedIDs.contains($0.id) }
            return Resolution(payload: payload, newSelection: selectedIDs)
        }
        return Resolution(payload: [draggedItem], newSelection: [draggedItem.id])
    }

    static func fileURLs(for payload: [ScreenshotItem]) -> [URL] {
        payload.compactMap { item in
            guard let url = item.fileURL else { return nil }
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }
}
