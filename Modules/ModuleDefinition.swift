import SwiftUI

@MainActor
protocol IslandModule {

    var id: String { get }

    var title: String { get }

    var systemImage: String { get }

    func makeContent() -> AnyView

    func makeCompactContent() -> AnyView

    var providesCompactSummary: Bool { get }
}

extension IslandModule {
    func makeCompactContent() -> AnyView { AnyView(EmptyView()) }
    var providesCompactSummary: Bool { false }
}

@MainActor
final class ModuleRegistry: ObservableObject {
    static let shared = ModuleRegistry()

    let modules: [any IslandModule]

    init(modules: [any IslandModule]? = nil) {
        self.modules = modules
            ?? [ScreenshotBufferModule(), NowPlayingModule(), AgentsModule(), AttentionModule()]
    }

    func module(withID id: String) -> (any IslandModule)? {
        modules.first { $0.id == id }
    }

    var defaultModuleID: String {
        modules.first?.id ?? ""
    }

    var compactModule: (any IslandModule)? {
        modules.first { $0.providesCompactSummary }
    }
}

struct ScreenshotBufferModule: IslandModule {
    let id = "screenshots"
    let title = "Screenshots"
    let systemImage = "photo.on.rectangle"

    func makeContent() -> AnyView {
        AnyView(ScreenshotBufferView())
    }
}

struct AgentsModule: IslandModule {
    let id = "agents"
    let title = "AI Agents"
    let systemImage = "cpu"

    func makeContent() -> AnyView {
        AnyView(AgentMonitorView())
    }
}

struct AttentionModule: IslandModule {
    let id = "attention"
    let title = "Attention"
    let systemImage = "bell.badge"

    func makeContent() -> AnyView {
        AnyView(AttentionCenterView())
    }
}

struct NowPlayingModule: IslandModule {
    let id = "nowPlaying"
    let title = "Now Playing"
    let systemImage = "music.note"
    let providesCompactSummary = true

    func makeContent() -> AnyView {
        AnyView(NowPlayingView())
    }

    func makeCompactContent() -> AnyView {
        AnyView(NowPlayingCompactView())
    }
}
