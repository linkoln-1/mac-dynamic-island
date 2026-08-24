import XCTest
@testable import PersonalIsland

@MainActor
final class AppSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "settings-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsAndRoundtrip() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.hoverOpenEnabled)
        XCTAssertEqual(settings.hoverExpandDelay, 0.2)
        XCTAssertEqual(settings.agentAutoClearSeconds, 60)
        XCTAssertEqual(settings.screenshotBufferLimit, 30)
        XCTAssertEqual(settings.attentionRetentionDays, 7)

        settings.hoverOpenEnabled = false
        settings.hoverExpandDelay = 0.4
        settings.agentAutoClearSeconds = 120
        settings.screenshotBufferLimit = 50
        settings.attentionRetentionDays = 14

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.hoverOpenEnabled)
        XCTAssertEqual(reloaded.hoverExpandDelay, 0.4)
        XCTAssertEqual(reloaded.agentAutoClearSeconds, 120)
        XCTAssertEqual(reloaded.screenshotBufferLimit, 50)
        XCTAssertEqual(reloaded.attentionRetentionDays, 14)
    }

    func testNotificationGatingByKindAndProvider() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.allowsNotification(kind: .finished, provider: .claude))

        settings.notifyFinished = false
        XCTAssertFalse(settings.allowsNotification(kind: .finished, provider: .claude))
        XCTAssertTrue(settings.allowsNotification(kind: .failed, provider: .claude))

        settings.notifyCodex = false
        XCTAssertFalse(settings.allowsNotification(kind: .failed, provider: .codex))
        XCTAssertTrue(settings.allowsNotification(kind: .failed, provider: .claude))
    }

    func testAgentStoreUsesLiveRetention() {
        var virtualNow = Date(timeIntervalSince1970: 300_000)
        let store = AgentStore(now: { virtualNow })
        store.liveFinishedRetention = { 30 }
        store.ingest(AgentWireEvent(
            provider: .claude, event: "UserPromptSubmit", sessionID: "s1",
            timestamp: 0, cwd: "/tmp/p", toolName: nil, activityDetail: nil,
            notificationType: nil, dedupKey: "a1"
        ))
        virtualNow = virtualNow.addingTimeInterval(5)
        store.ingest(AgentWireEvent(
            provider: .claude, event: "Stop", sessionID: "s1",
            timestamp: 0, cwd: "/tmp/p", toolName: nil, activityDetail: nil,
            notificationType: nil, dedupKey: "a2"
        ))
        virtualNow = virtualNow.addingTimeInterval(40)
        store.sweep()
        XCTAssertTrue(store.sessions.isEmpty, "live retention 30s must override policy 60s")
    }

    func testAttentionStoreUsesLiveMaxAge() {
        var virtualNow = Date(timeIntervalSince1970: 400_000)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-attn-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AttentionStore(
            persistence: AttentionPersistence(directory: dir), now: { virtualNow }
        )
        store.liveMaxAge = { 3600 }
        store.publish(AttentionEvent(
            dedupKey: "k1", source: .agent(.claude), kind: .finished, priority: .normal,
            title: "Claude Code", subtitle: "p · C-0001", detail: "Finished",
            provider: .claude, projectName: "p", projectPath: nil, sessionAlias: "C-0001",
            relatedAgentSessionID: "claude:s1", relatedWorkCycleID: 1
        ))
        store.markRead("k1")
        virtualNow = virtualNow.addingTimeInterval(2 * 3600)
        store.publish(AttentionEvent(
            dedupKey: "k2", source: .agent(.claude), kind: .finished, priority: .normal,
            title: "Claude Code", subtitle: "p · C-0002", detail: "Finished",
            provider: .claude, projectName: "p", projectPath: nil, sessionAlias: "C-0002",
            relatedAgentSessionID: "claude:s2", relatedWorkCycleID: 1
        ))
        XCTAssertNil(store.items["k1"], "2h-old read item must expire under live 1h maxAge")
        XCTAssertNotNil(store.items["k2"])
    }

    func testHoverDisabledBlocksAutoExpand() {
        let state = IslandState(
            hoverPolicy: IslandHoverPolicy(expandDelay: 0.05, collapseGrace: 0.05)
        )
        state.hoverOpenProvider = { false }
        state.hoverChanged(true)
        let expectation = expectation(description: "delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { expectation.fulfill() }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(state.mode, .collapsed, "hover-open disabled must not expand")
        XCTAssertTrue(state.isHovering, "visual hover feedback still tracked")
    }

    func testIslandStateUsesLivePolicy() {
        let state = IslandState(
            hoverPolicy: IslandHoverPolicy(expandDelay: 30, collapseGrace: 30)
        )
        state.livePolicy = { IslandHoverPolicy(expandDelay: 0.05, collapseGrace: 0.05) }
        state.hoverChanged(true)
        let expectation = expectation(description: "delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(state.mode, .expanded, "live policy 0.05s must override injected 30s")
    }

    func testModuleOrderDefaultsAndCustom() {
        let settings = AppSettings(defaults: defaults)
        let all = ["a", "b", "c"]
        XCTAssertEqual(settings.orderedModuleIDs(all: all), ["a", "b", "c"])

        settings.moduleOrder = ["c", "ghost", "a"]
        XCTAssertEqual(settings.orderedModuleIDs(all: all), ["c", "a", "b"])

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.orderedModuleIDs(all: all), ["c", "a", "b"])
    }

    func testMoveModuleSwapsAndClamps() {
        let settings = AppSettings(defaults: defaults)
        let all = ["a", "b", "c"]
        settings.moveModule("c", offset: -1, all: all)
        XCTAssertEqual(settings.orderedModuleIDs(all: all), ["a", "c", "b"])
        settings.moveModule("a", offset: -1, all: all)
        XCTAssertEqual(settings.orderedModuleIDs(all: all), ["a", "c", "b"])
        settings.moveModule("b", offset: 1, all: all)
        XCTAssertEqual(settings.orderedModuleIDs(all: all), ["a", "c", "b"])
        settings.moveModule("ghost", offset: 1, all: all)
        XCTAssertEqual(settings.orderedModuleIDs(all: all), ["a", "c", "b"])
    }

    func testOnboardingFlagPreventsSecondShow() {
        XCTAssertFalse(defaults.bool(forKey: OnboardingController.defaultsKey))
        defaults.set(true, forKey: OnboardingController.defaultsKey)
        XCTAssertFalse(OnboardingController.shared.showIfNeeded(defaults: defaults))
    }

    func testScreenshotBufferUsesLiveLimit() {
        let buffer = ScreenshotBuffer(maxItems: 30)
        buffer.liveLimit = { 2 }
        for index in 0..<4 {
            _ = buffer.insert(ScreenshotItem(source: .clipboard, pngHash: "hash-\(index)"))
        }
        XCTAssertEqual(buffer.items.count, 2)
    }
}
