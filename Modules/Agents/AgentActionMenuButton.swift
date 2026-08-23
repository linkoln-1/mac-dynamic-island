import AppKit
import SwiftUI

struct AgentActionMenuButton: View {
    let projectPath: String?
    @ObservedObject private var lang = AppLanguageManager.shared

    var body: some View {
        AgentActionMenuHost(projectPath: projectPath)
            .frame(width: 18, height: 18)
            .help(lang.string("agent.actions.help"))
            .accessibilityLabel(lang.string("agent.actions.help"))
    }
}

private struct AgentActionMenuHost: NSViewRepresentable {
    let projectPath: String?

    func makeNSView(context: Context) -> AgentActionMenuNSView {
        AgentActionMenuNSView()
    }

    func updateNSView(_ nsView: AgentActionMenuNSView, context: Context) {
        nsView.projectPath = projectPath
    }
}

final class AgentActionMenuNSView: NSView {
    var projectPath: String?
    var actions = AgentProjectActions()

    override func draw(_ dirtyRect: NSRect) {
        let symbol = NSImage(
            systemSymbolName: "ellipsis.circle", accessibilityDescription: "Project actions"
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        guard let symbol else { return }
        let tinted = symbol.tinted(with: NSColor.white.withAlphaComponent(0.7))
        let size = tinted.size
        tinted.draw(in: NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        ))
    }

    override func mouseDown(with event: NSEvent) {
        showMenu(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu(with: event)
    }

    private func showMenu(with event: NSEvent) {
        guard let projectPath, actions.isAvailable(path: projectPath) else { return }
        let lang = AppLanguageManager.shared
        let menu = NSMenu()
        menu.addItem(makeItem(lang.string("action.openProject"), action: #selector(openProject)))
        menu.addItem(makeItem(lang.string("action.revealInFinder"), action: #selector(revealInFinder)))
        menu.addItem(makeItem(lang.string("action.copyProjectPath"), action: #selector(copyProjectPath)))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func makeItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openProject() {
        guard let projectPath else { return }
        actions.openProject(path: projectPath)
    }

    @objc private func revealInFinder() {
        guard let projectPath else { return }
        actions.reveal(path: projectPath)
    }

    @objc private func copyProjectPath() {
        guard let projectPath else { return }
        actions.copyPath(path: projectPath)
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: size)
        draw(in: rect)
        rect.fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
