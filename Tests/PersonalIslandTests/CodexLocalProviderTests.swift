import Combine
import XCTest
@testable import PersonalIsland

@MainActor
final class CodexLocalProviderTests: XCTestCase {
    private var tempDir: URL!
    private var agentStore: AgentStore!
    private var attentionStore: AttentionStore!
    private var notified: [AttentionItem] = []
    private var subscriptions = Set<AnyCancellable>()
    private var virtualNow = Date(timeIntervalSince1970: 200_000)

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("2026/08/23"), withIntermediateDirectories: true
        )
        agentStore = AgentStore(now: { self.virtualNow })
        attentionStore = AttentionStore(
            persistence: AttentionPersistence(
                directory: tempDir.appendingPathComponent("attention")
            ),
            now: { self.virtualNow }
        )
        notified = []
        subscriptions = []
        attentionStore.notificationRequests.sink { self.notified.append($0) }.store(in: &subscriptions)
        agentStore.transitions.sink { transition in
            guard let event = AgentAttentionMapper.event(for: transition) else { return }
            self.attentionStore.publish(event)
        }.store(in: &subscriptions)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeProvider() -> CodexLocalSessionProvider {
        CodexLocalSessionProvider(root: tempDir) { [weak self] events in
            for event in events { self?.agentStore.ingest(event) }
        }
    }

    private func rolloutURL(_ name: String = "rollout-2026-08-23T21-50-56-abcd1234.jsonl") -> URL {
        tempDir.appendingPathComponent("2026/08/23/\(name)")
    }

    private func metaLine(id: String = "01a02ff6-285a-7b51-be8b-3132e40130dd", cwd: String = "/tmp/sandbox") -> String {
        "{\"timestamp\":\"t\",\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\",\"cwd\":\"\(cwd)\",\"originator\":\"Codex Desktop\"}}"
    }

    private let taskStarted = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}"
    private let taskComplete = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}"
    private let execCall = "{\"type\":\"response_item\",\"payload\":{\"type\":\"custom_tool_call\",\"name\":\"exec\"}}"

    private func write(_ lines: [String], to url: URL) throws {
        try (lines.joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: url)
    }

    private func append(_ lines: [String], to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: (lines.joined(separator: "\n") + "\n").data(using: .utf8)!)
        try handle.close()
    }

    func testLiveRolloutCreatesWorkingSessionWithCoarseActivity() throws {
        let url = rolloutURL()
        try write([metaLine()], to: url)
        let provider = makeProvider()
        provider.tail(fileURL: url)
        try append([taskStarted, execCall], to: url)
        provider.tail(fileURL: url)

        let session = agentStore.orderedSessions(provider: .codex).first
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.state, .working)
        XCTAssertEqual(session?.activity, "Running a command")
        XCTAssertEqual(session?.project, "sandbox")
        XCTAssertTrue(notified.isEmpty)
    }

    func testTaskCompleteFinishesWithOneItemAndOneNotification() throws {
        let url = rolloutURL()
        try write([metaLine(), taskStarted, execCall], to: url)
        let provider = makeProvider()
        provider.tail(fileURL: url)
        virtualNow = virtualNow.addingTimeInterval(10)
        try append([taskComplete], to: url)
        provider.tail(fileURL: url)

        let session = agentStore.orderedSessions(provider: .codex).first
        XCTAssertEqual(session?.state, .finished)
        XCTAssertEqual(attentionStore.sortedItems().filter { $0.kind == .finished }.count, 1)
        XCTAssertEqual(notified.count, 1)
        XCTAssertEqual(notified[0].provider, .codex)
    }

    func testCatchUpImportsActiveSessionWithoutNotifications() throws {
        let url = rolloutURL()
        try write([metaLine(), taskStarted, taskComplete, taskStarted, execCall], to: url)
        let provider = makeProvider()
        provider.catchUp(fileURL: url)

        let session = agentStore.orderedSessions(provider: .codex).first
        XCTAssertEqual(session?.state, .working)
        XCTAssertEqual(session?.cycleID, 2)
        XCTAssertEqual(session?.activity, "Running a command")
        XCTAssertTrue(notified.isEmpty, "reconciliation must not notify")
        XCTAssertTrue(attentionStore.sortedItems().isEmpty)
    }

    func testCatchUpSkipsFinishedHistoricalSession() throws {
        let url = rolloutURL()
        try write([metaLine(), taskStarted, execCall, taskComplete], to: url)
        let provider = makeProvider()
        provider.catchUp(fileURL: url)

        XCTAssertTrue(agentStore.orderedSessions(provider: .codex).isEmpty)
        XCTAssertTrue(notified.isEmpty)
    }

    func testLiveFinishAfterCatchUpNotifiesExactlyOnce() throws {
        let url = rolloutURL()
        try write([metaLine(), taskStarted, execCall], to: url)
        let provider = makeProvider()
        provider.catchUp(fileURL: url)
        XCTAssertTrue(notified.isEmpty)

        virtualNow = virtualNow.addingTimeInterval(20)
        try append([taskComplete], to: url)
        provider.tail(fileURL: url)
        provider.tail(fileURL: url)

        XCTAssertEqual(agentStore.orderedSessions(provider: .codex).first?.state, .finished)
        XCTAssertEqual(notified.count, 1)
    }

    func testTwoFilesSameProjectStayDistinctSessions() throws {
        let urlA = rolloutURL("rollout-2026-08-23T10-00-00-aaaa.jsonl")
        let urlB = rolloutURL("rollout-2026-08-23T11-00-00-bbbb.jsonl")
        try write([metaLine(id: "sess-aaaa", cwd: "/tmp/same"), taskStarted], to: urlA)
        try write([metaLine(id: "sess-bbbb", cwd: "/tmp/same"), taskStarted], to: urlB)
        let provider = makeProvider()
        provider.catchUp(fileURL: urlA)
        provider.catchUp(fileURL: urlB)

        let sessions = agentStore.orderedSessions(provider: .codex)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(Set(sessions.map(\.sessionID)), ["sess-aaaa", "sess-bbbb"])
    }

    func testMalformedLinesIgnoredSafely() throws {
        let url = rolloutURL()
        try write([metaLine(), "not json {{{", "", taskStarted], to: url)
        let provider = makeProvider()
        provider.tail(fileURL: url)
        XCTAssertEqual(agentStore.orderedSessions(provider: .codex).first?.state, .working)
    }

    func testPartialLineTailingProducesNoDuplicates() throws {
        let url = rolloutURL()
        try write([metaLine(), taskStarted], to: url)
        let provider = makeProvider()
        provider.tail(fileURL: url)
        let half = String(taskComplete.prefix(20))
        let rest = String(taskComplete.dropFirst(20))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: half.data(using: .utf8)!)
        try handle.close()
        provider.tail(fileURL: url)
        XCTAssertEqual(agentStore.orderedSessions(provider: .codex).first?.state, .working)

        virtualNow = virtualNow.addingTimeInterval(10)
        try append([rest], to: url)
        provider.tail(fileURL: url)
        XCTAssertEqual(agentStore.orderedSessions(provider: .codex).first?.state, .finished)
        XCTAssertEqual(notified.count, 1)
    }

    func testHookAuthoritySuppressesFallbackEvents() throws {
        let url = rolloutURL()
        try write([metaLine(id: "hooked-session"), taskStarted], to: url)
        let provider = makeProvider()
        provider.isHookAuthority = { $0 == "hooked-session" }
        provider.catchUp(fileURL: url)
        provider.tail(fileURL: url)

        XCTAssertTrue(agentStore.orderedSessions(provider: .codex).isEmpty)
    }

    func testHealthUnavailableWhenDirectoryMissing() {
        let provider = CodexLocalSessionProvider(
            root: tempDir.appendingPathComponent("missing-dir")
        ) { _ in }
        provider.start()
        XCTAssertEqual(provider.health, .unavailable)
    }

    func testReconcileRecentFilesRespectsWindow() throws {
        let recent = rolloutURL("rollout-2026-08-23T21-00-00-recent.jsonl")
        try write([metaLine(id: "recent-one"), taskStarted], to: recent)
        let old = rolloutURL("rollout-2026-08-23T01-00-00-old.jsonl")
        try write([metaLine(id: "old-one"), taskStarted], to: old)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-24 * 3600)], ofItemAtPath: old.path
        )
        let provider = makeProvider()
        provider.reconcileRecentFiles()

        let ids = Set(agentStore.orderedSessions(provider: .codex).map(\.sessionID))
        XCTAssertEqual(ids, ["recent-one"], "old history must not become active cards")
    }

    func testLazySessionCreationFromStopWithoutSessionStart() {
        agentStore.ingest(AgentWireEvent(
            provider: .codex, event: "Stop", sessionID: "lazy-stop",
            timestamp: virtualNow.timeIntervalSince1970, cwd: "/tmp/lazy",
            toolName: nil, activityDetail: nil, notificationType: nil, dedupKey: "lz1"
        ))
        let session = agentStore.sessions["codex:lazy-stop"]
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.state, .finished)
    }

    func testCodexNotificationLocalizedViaExistingPipeline() throws {
        let suite = "codex-loc-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(AppLanguageMode.russian.rawValue, forKey: AppLanguageManager.defaultsKey)
        let lang = AppLanguageManager(defaults: defaults, preferredLanguages: { ["en-US"] })

        let url = rolloutURL()
        try write([metaLine(), taskStarted], to: url)
        let provider = makeProvider()
        provider.tail(fileURL: url)
        virtualNow = virtualNow.addingTimeInterval(10)
        try append([taskComplete], to: url)
        provider.tail(fileURL: url)

        let item = notified[0]
        XCTAssertEqual(AttentionPresentation.kindLabel(item.kind, lang: lang), "Завершено")
        XCTAssertEqual(item.title, "Codex")
        defaults.removePersistentDomain(forName: suite)
    }
}
