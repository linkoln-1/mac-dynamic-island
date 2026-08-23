import AppKit
import SwiftUI
import Combine

@MainActor
final class IslandWindowController {
    let state: IslandState

    private(set) var panel: IslandPanel?
    private var previousScreenFrames: Set<String> = []
    private var outsideClickMonitor: Any?
    private var localEventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    #if DEBUG
    private var debugMouseMonitor: Any?
    #endif

    init(state: IslandState) {
        self.state = state
    }

    func start() {
        rebuild()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        }
        state.$mode
            .removeDuplicates()
            .sink { [weak self] mode in
                Task { @MainActor in self?.modeChanged(mode) }
            }
            .store(in: &cancellables)
    }

    private static func screenFrameSnapshot() -> Set<String> {
        Set(NSScreen.screens.map { NSStringFromRect($0.frame) })
    }

    private func screensChanged() {
        let frames = Self.screenFrameSnapshot()
        guard frames != previousScreenFrames else { return }
        Log.island.info("Screen parameters changed — rebuilding island panel")
        rebuild()
    }

    func rebuild() {
        removeMonitors()
        if let panel {
            NotchSpaceManager.shared.remove(panel)
            panel.close()
        }
        panel = nil
        previousScreenFrames = Self.screenFrameSnapshot()

        guard let screen = targetScreen() else {
            Log.island.warning("No screen available — island not shown")
            return
        }
        state.closedSize = NotchGeometryProvider.closedSize(for: screen)
        state.settleToBaseline()

        let newPanel = IslandPanel()

        let container = IslandHitTestContainerView(state: state)
        let hosting = NSHostingView(rootView: IslandRootView(state: state))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        newPanel.contentView = container
        position(newPanel, on: screen)
        newPanel.orderFrontRegardless()
        NotchSpaceManager.shared.add(newPanel)
        panel = newPanel
        Log.island.info("Island panel created on screen \(NSStringFromRect(screen.frame))")

        #if DEBUG

        if ProcessInfo.processInfo.environment["PI_DEBUG_GEOMETRY"] == "1" {
            installGeometryDebug(panel: newPanel, container: container, hosting: hosting)
        }
        #endif
    }

    #if DEBUG
    private func installGeometryDebug(
        panel: IslandPanel, container: NSView, hosting: NSView
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak panel, weak container, weak hosting] in
            guard let self, let panel, let container, let hosting else { return }
            let rect = IslandHitTest.interactiveRect(
                mode: self.state.mode, closedSize: self.state.closedSize, bounds: container.bounds
            )
            var wsBounds = "unknown"
            if let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(panel.windowNumber)) as? [[String: Any]],
               let bounds = list.first?[kCGWindowBounds as String] {
                wsBounds = String(describing: bounds)
            }
            print("PI_GEO appkit.panel.frame=\(NSStringFromRect(panel.frame))")
            print("PI_GEO windowserver.bounds(topLeftOrigin)=\(wsBounds)")
            print("PI_GEO container.frame=\(NSStringFromRect(container.frame)) flipped=\(container.isFlipped)")
            print("PI_GEO hosting.frame=\(NSStringFromRect(hosting.frame)) flipped=\(hosting.isFlipped) safeArea=\(hosting.safeAreaInsets)")
            print("PI_GEO interactiveRect(bottomLeftOrigin)=\(NSStringFromRect(rect)) mode=\(self.state.mode.rawValue)")
        }

        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                let window = note.object as? NSWindow
                let isPanel = window is IslandPanel
                print("PI_GEO focus \(name.rawValue) isIslandPanel=\(isPanel) appKeyWindow=\(String(describing: NSApp.keyWindow)) at=\(Date().timeIntervalSince1970)")
            }
        }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                print("PI_GEO focus app=\(name.rawValue) at=\(Date().timeIntervalSince1970)")
            }
        }

        var lastLog = Date.distantPast
        let handler: (NSEvent, String) -> Void = { [weak panel] _, kind in
            guard let panel else { return }
            let now = Date()
            guard kind == "down" || now.timeIntervalSince(lastLog) > 0.5 else { return }
            lastLog = now
            let screenPoint = NSEvent.mouseLocation
            let windowPoint = panel.convertPoint(fromScreen: screenPoint)
            let viewPoint = panel.contentView?.convert(windowPoint, from: nil) ?? .zero
            let yTop = (panel.contentView?.bounds.height ?? 0) - viewPoint.y
            print("PI_GEO mouse[\(kind)] screen=\(screenPoint) window=\(windowPoint) view=\(viewPoint) viewYTop=\(yTop) at=\(Date().timeIntervalSince1970)")
        }
        debugMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown]
        ) { event in
            handler(event, event.type == .leftMouseDown ? "down" : "move")
        }
        _ = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
        ) { event in
            switch event.type {
            case .leftMouseDown: handler(event, "down-local")
            case .rightMouseDown: handler(event, "right-local")
            case .otherMouseDown: handler(event, "other-local")
            case .keyDown:
                print("PI_GEO key[local] keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "?") at=\(Date().timeIntervalSince1970)")
            case .scrollWheel:
                handler(event, "scroll-local")
            default: break
            }
            return event
        }
    }
    #endif

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: NotchGeometryProvider.hasNotch)
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func position(_ panel: NSPanel, on screen: NSScreen) {
        let frame = screen.frame
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.maxY - panel.frame.height
        ))
    }

    private func modeChanged(_ mode: IslandMode) {
        if mode == .expanded {
            installMonitors()
        } else {
            removeMonitors()
        }
    }

    private func expandedIslandFrame() -> CGRect {
        guard let panel else { return .zero }
        let frame = panel.frame
        return CGRect(
            x: frame.midX - IslandMetrics.expandedSize.width / 2,
            y: frame.maxY - IslandMetrics.expandedSize.height,
            width: IslandMetrics.expandedSize.width,
            height: IslandMetrics.expandedSize.height
        )
    }

    private func installMonitors() {
        guard panel != nil else { return }

        if outsideClickMonitor == nil {

            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.state.mode == .expanded else { return }
                    if !self.expandedIslandFrame().contains(NSEvent.mouseLocation) {
                        self.state.dismissExpanded()
                    }
                }
            }
        }
        if localEventMonitor == nil {

            localEventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                guard let self else { return event }

                MainActor.assumeIsolated { self.handleLocalClick(event) }
                return event
            }
        }
    }

    private func handleLocalClick(_ event: NSEvent) {
        guard state.mode == .expanded, event.window !== panel else { return }
        state.dismissExpanded()
    }

    private func removeMonitors() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
}
