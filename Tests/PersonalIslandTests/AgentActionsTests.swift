import XCTest
@testable import PersonalIsland

final class AgentActionsTests: XCTestCase {
    private final class RecordingWorkspace: WorkspaceOpening {
        var opened: [URL] = []
        var revealed: [URL] = []
        func open(_ url: URL) { opened.append(url) }
        func reveal(_ url: URL) { revealed.append(url) }
    }

    private final class RecordingPasteboard: PasteboardWriting {
        var written: [String] = []
        func write(_ string: String) { written.append(string) }
    }

    private var tempDir: URL!
    private var workspace: RecordingWorkspace!
    private var pasteboard: RecordingPasteboard!
    private var actions: AgentProjectActions!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("actions-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        workspace = RecordingWorkspace()
        pasteboard = RecordingPasteboard()
        actions = AgentProjectActions(workspace: workspace, pasteboard: pasteboard)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testAvailabilityRequiresExistingDirectory() {
        XCTAssertTrue(actions.isAvailable(path: tempDir.path))
        XCTAssertFalse(actions.isAvailable(path: tempDir.path + "/missing"))
        XCTAssertFalse(actions.isAvailable(path: nil))
        XCTAssertFalse(actions.isAvailable(path: ""))

        let file = tempDir.appendingPathComponent("file.txt")
        try? Data().write(to: file)
        XCTAssertFalse(actions.isAvailable(path: file.path))
    }

    func testRevealUsesWorkspaceOnlyWhenAvailable() {
        actions.reveal(path: tempDir.path)
        XCTAssertEqual(workspace.revealed.map(\.path), [tempDir.path])

        actions.reveal(path: tempDir.path + "/missing")
        XCTAssertEqual(workspace.revealed.count, 1)
    }

    func testCopyPathWritesToPasteboard() {
        actions.copyPath(path: tempDir.path)
        XCTAssertEqual(pasteboard.written, [tempDir.path])
    }

    func testOpenProjectPrefersWorkspaceThenProjectThenDirectory() throws {
        actions.openProject(path: tempDir.path)
        XCTAssertEqual(workspace.opened.last?.path, tempDir.path)

        let project = tempDir.appendingPathComponent("App.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        actions.openProject(path: tempDir.path)
        XCTAssertEqual(workspace.opened.last?.lastPathComponent, "App.xcodeproj")

        let ws = tempDir.appendingPathComponent("App.xcworkspace", isDirectory: true)
        try FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
        actions.openProject(path: tempDir.path)
        XCTAssertEqual(workspace.opened.last?.lastPathComponent, "App.xcworkspace")
    }

    func testOpenProjectMissingPathDoesNothing() {
        actions.openProject(path: tempDir.path + "/missing")
        XCTAssertTrue(workspace.opened.isEmpty)
    }

    func testOpenAppActivatesExistingBundleOnly() {
        actions.openApp(path: tempDir.path)
        XCTAssertEqual(workspace.opened.last?.path, tempDir.path)
        actions.openApp(path: tempDir.path + "/missing.app")
        XCTAssertEqual(workspace.opened.count, 1)
    }

    @MainActor
    func testHostAppPathFlowsIntoSession() {
        let store = AgentStore()
        store.ingest(AgentWireEvent(
            provider: .claude, event: "UserPromptSubmit", sessionID: "host-test",
            timestamp: 0, cwd: "/tmp/p", toolName: nil, activityDetail: nil,
            notificationType: nil, dedupKey: "h1", hostAppPath: "/Applications/iTerm.app"
        ))
        XCTAssertEqual(store.sessions["claude:host-test"]?.hostAppPath, "/Applications/iTerm.app")

        store.ingest(AgentWireEvent(
            provider: .claude, event: "PreToolUse", sessionID: "host-test",
            timestamp: 0, cwd: "/tmp/p", toolName: "Bash", activityDetail: "ls",
            notificationType: nil, dedupKey: "h2", hostAppPath: nil
        ))
        XCTAssertEqual(store.sessions["claude:host-test"]?.hostAppPath, "/Applications/iTerm.app")
    }

    func testFocusCapabilitiesAreUnavailableByDesign() {
        XCTAssertFalse(AgentSessionFocusCapability.claudeExactSession)
        XCTAssertFalse(AgentSessionFocusCapability.codexCLIExactSession)
        XCTAssertFalse(AgentSessionFocusCapability.codexDesktopDeepLink)
    }

    @MainActor
    func testNavigateToMissingSessionDoesNothing() {
        let controller = AgentsModuleController.shared
        controller.navigateToSession("claude:nonexistent-session")
        XCTAssertNil(controller.highlightedSessionID)
    }
}
