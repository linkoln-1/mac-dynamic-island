import AppKit
import SwiftUI

struct CardMenuEntry {
    let title: String
    let action: () -> Void
}

struct ScreenshotCardInteraction: NSViewRepresentable {
    let tooltip: String?
    let onClick: (_ commandKey: Bool) -> Void
    let onDoubleClick: () -> Void
    let onHover: (Bool) -> Void

    let dragPayloadProvider: () -> [(url: URL, preview: NSImage?)]
    let menuEntries: () -> [CardMenuEntry?]

    func makeNSView(context: Context) -> CardInteractionNSView {
        let view = CardInteractionNSView()
        update(view)
        return view
    }

    func updateNSView(_ view: CardInteractionNSView, context: Context) {
        update(view)
    }

    private func update(_ view: CardInteractionNSView) {
        view.toolTip = tooltip
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.onHover = onHover
        view.dragPayloadProvider = dragPayloadProvider
        view.menuEntries = menuEntries
    }
}

final class CardInteractionNSView: NSView, NSDraggingSource {
    var onClick: ((Bool) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var dragPayloadProvider: (() -> [(url: URL, preview: NSImage?)])?
    var menuEntries: (() -> [CardMenuEntry?])?

    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false
    private var menuActions: [CardMenuEntry] = []

    private static let dragThreshold: CGFloat = 4

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downEvent = mouseDownEvent, !didStartDrag else { return }
        let start = convert(downEvent.locationInWindow, from: nil)
        let current = convert(event.locationInWindow, from: nil)
        guard hypot(current.x - start.x, current.y - start.y) > Self.dragThreshold else { return }
        didStartDrag = true
        beginDrag(with: downEvent)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard !didStartDrag else { return }
        if event.clickCount == 2 {
            onDoubleClick?()
        } else if event.clickCount == 1 {
            onClick?(event.modifierFlags.contains(.command))
        }
    }

    private func beginDrag(with event: NSEvent) {
        guard let payload = dragPayloadProvider?(), !payload.isEmpty else { return }
        Log.screenshots.info("Beginning drag session with \(payload.count) item(s)")

        let items = payload.enumerated().map { index, entry -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: entry.url as NSURL)

            let offset = CGFloat(min(index, 3)) * 4
            let frame = bounds.offsetBy(dx: offset, dy: -offset)
            let image = entry.preview
                ?? NSWorkspace.shared.icon(forFile: entry.url.path)
            item.setDraggingFrame(frame, contents: image)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {

        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        NotificationCenter.default.post(name: .islandDragSessionBegan, object: nil)
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        NotificationCenter.default.post(name: .islandDragSessionEnded, object: nil)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let entries = (menuEntries?() ?? []).compactMap { $0 }
        guard !entries.isEmpty else { return nil }
        menuActions = entries
        let menu = NSMenu()
        for (index, entry) in entries.enumerated() {
            if entry.title == "-" {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: entry.title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        return menu
    }

    @objc private func runMenuAction(_ sender: NSMenuItem) {
        guard menuActions.indices.contains(sender.tag) else { return }
        menuActions[sender.tag].action()
    }
}
