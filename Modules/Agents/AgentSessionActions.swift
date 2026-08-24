import AppKit
import Foundation

protocol PasteboardWriting {
    func write(_ string: String)
}

struct SystemPasteboard: PasteboardWriting {
    func write(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

protocol WorkspaceOpening {
    func open(_ url: URL)
    func reveal(_ url: URL)
}

struct SystemWorkspace: WorkspaceOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

struct AgentProjectActions {
    var fileManager: FileManager = .default
    var workspace: WorkspaceOpening = SystemWorkspace()
    var pasteboard: PasteboardWriting = SystemPasteboard()

    func isAvailable(path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    func reveal(path: String) {
        guard isAvailable(path: path) else { return }
        workspace.reveal(URL(fileURLWithPath: path))
    }

    func copyPath(path: String) {
        pasteboard.write(path)
    }

    func openApp(path: String) {
        guard isAvailable(path: path) else { return }
        workspace.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    func openProject(path: String) {
        guard isAvailable(path: path) else { return }
        if let container = projectContainer(in: path) {
            workspace.open(container)
        } else {
            workspace.open(URL(fileURLWithPath: path, isDirectory: true))
        }
    }

    func projectContainer(in path: String) -> URL? {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: path) else { return nil }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        if let workspaceEntry = entries.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return root.appendingPathComponent(workspaceEntry)
        }
        if let projectEntry = entries.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return root.appendingPathComponent(projectEntry)
        }
        return nil
    }
}

enum AgentSessionFocusCapability {
    static let claudeExactSession = false
    static let codexCLIExactSession = false
    static let codexDesktopDeepLink = false
}
