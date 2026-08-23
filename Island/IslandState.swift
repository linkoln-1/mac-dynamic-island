import SwiftUI
import Combine

enum IslandMode: String, CaseIterable, Equatable {

    case collapsed

    case compact

    case expanded
}

struct IslandHoverPolicy {

    var expandDelay: TimeInterval = 0.2

    var collapseGrace: TimeInterval = 0.75
}

extension Notification.Name {
    static let islandDragSessionBegan = Notification.Name("PIIslandDragSessionBegan")
    static let islandDragSessionEnded = Notification.Name("PIIslandDragSessionEnded")
    static let islandNavigateToModule = Notification.Name("PIIslandNavigateToModule")
}

@MainActor
final class IslandState: ObservableObject {
    @Published private(set) var mode: IslandMode = .collapsed
    @Published var selectedModuleID: String

    @Published var isHovering: Bool = false

    @Published var closedSize: CGSize = IslandMetrics.fallbackClosedSize

    @Published private(set) var isCompactAvailable: Bool = false

    @Published var compactWidthBonus: CGFloat = 0

    @Published var compactShowsAgentsOnly: Bool = false

    let registry: ModuleRegistry

    private let hoverPolicy: IslandHoverPolicy
    var livePolicy: (() -> IslandHoverPolicy)?
    var hoverOpenProvider: (() -> Bool)?
    private var hoverExpandWork: DispatchWorkItem?
    private var hoverCollapseWork: DispatchWorkItem?

    private var isDragOutActive = false
    private var dragObservers: [NSObjectProtocol] = []

    init(registry: ModuleRegistry? = nil, hoverPolicy: IslandHoverPolicy = IslandHoverPolicy()) {
        let resolved = registry ?? .shared
        self.registry = resolved
        self.selectedModuleID = resolved.defaultModuleID
        self.hoverPolicy = hoverPolicy
        observeDragActivity()
    }

    deinit {
        for observer in dragObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var selectedModule: (any IslandModule)? {
        registry.module(withID: selectedModuleID)
    }

    var compactModule: (any IslandModule)? {
        registry.compactModule
    }

    func expand() {
        guard mode != .expanded else { return }
        mode = .expanded
        Log.island.info("Island expanded")
        #if DEBUG
        if ProcessInfo.processInfo.environment["PI_DEBUG_GEOMETRY"] == "1" {
            print("PI_GEO mode=expanded at=\(Date().timeIntervalSince1970)")
        }
        #endif
    }

    func collapse() {
        guard mode != .collapsed else { return }
        mode = .collapsed
        Log.island.info("Island collapsed")
    }

    func showCompact() {
        guard mode != .compact else { return }
        mode = .compact
        Log.island.info("Island compact")
    }

    func handleIslandTap() {
        guard mode != .expanded else { return }
        if mode == .compact, compactShowsAgentsOnly {
            selectedModuleID = "agents"
        }
        expand()
    }

    private var effectiveHoverPolicy: IslandHoverPolicy {
        livePolicy?() ?? hoverPolicy
    }

    private var isHoverOpenEnabled: Bool {
        hoverOpenProvider?() ?? true
    }

    func hoverChanged(_ hovering: Bool) {
        isHovering = hovering
        guard isHoverOpenEnabled else {
            hoverExpandWork?.cancel()
            hoverExpandWork = nil
            hoverCollapseWork?.cancel()
            hoverCollapseWork = nil
            return
        }
        if hovering {
            hoverCollapseWork?.cancel()
            hoverCollapseWork = nil
            guard mode != .expanded, hoverExpandWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hoverExpandWork = nil
                guard self.isHovering else { return }
                self.handleIslandTap()
            }
            hoverExpandWork = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + effectiveHoverPolicy.expandDelay, execute: work
            )
        } else {
            hoverExpandWork?.cancel()
            hoverExpandWork = nil
            guard mode == .expanded else { return }
            scheduleHoverCollapse()
        }
    }

    private func scheduleHoverCollapse() {
        guard isHoverOpenEnabled else { return }
        hoverCollapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverCollapseWork = nil
            guard self.mode == .expanded, !self.isHovering, !self.isDragOutActive else { return }
            self.dismissExpanded()
        }
        hoverCollapseWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + effectiveHoverPolicy.collapseGrace, execute: work
        )
    }

    private func observeDragActivity() {
        let center = NotificationCenter.default
        dragObservers.append(center.addObserver(
            forName: .islandNavigateToModule, object: nil, queue: .main
        ) { [weak self] note in
            let moduleID = note.userInfo?["moduleID"] as? String
            Task { @MainActor in
                guard let self, let moduleID,
                      self.registry.module(withID: moduleID) != nil else { return }
                self.selectedModuleID = moduleID
                self.expand()
            }
        })
        dragObservers.append(center.addObserver(
            forName: .islandDragSessionBegan, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isDragOutActive = true }
        })
        dragObservers.append(center.addObserver(
            forName: .islandDragSessionEnded, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isDragOutActive = false

                if self.mode == .expanded, !self.isHovering {
                    self.scheduleHoverCollapse()
                }
            }
        })
    }

    func select(moduleID: String) {
        selectedModuleID = moduleID
        #if DEBUG
        if ProcessInfo.processInfo.environment["PI_DEBUG_GEOMETRY"] == "1" {
            print("PI_GEO select=\(moduleID) mode=\(mode.rawValue) at=\(Date().timeIntervalSince1970)")
        }
        #endif
    }

    func setCompactAvailable(_ available: Bool) {
        guard isCompactAvailable != available else { return }
        isCompactAvailable = available
        guard mode != .expanded else { return }
        settleToBaseline()
    }

    func dismissExpanded() {
        guard mode == .expanded else { return }
        settleToBaseline()
    }

    func settleToBaseline() {
        let target: IslandMode = isCompactAvailable ? .compact : .collapsed
        guard mode != target else { return }
        mode = target
        Log.island.info("Island settled to \(target.rawValue, privacy: .public)")
    }
}
