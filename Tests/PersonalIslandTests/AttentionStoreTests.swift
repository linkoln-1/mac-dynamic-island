import Combine
import XCTest
@testable import PersonalIsland

@MainActor
final class AttentionStoreTests: XCTestCase {
    private var virtualNow = Date(timeIntervalSince1970: 100_000)
    private var store: AttentionStore!
    private var agentStore: AgentStore!
    private var notified: [AttentionItem] = []
    private var subscriptions = Set<AnyCancellable>()
    private var tempDir: URL!

    override func setUp() {
        virtualNow = Date(timeIntervalSince1970: 100_000)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attention-tests-\(UUID().uuidString)", isDirectory: true)
        store = makeStore()
        agentStore = AgentStore(now: { self.virtualNow })
        notified = []
        subscriptions = []
        store.notificationRequests.sink { self.notified.append($0) }.store(in: &subscriptions)
        wireAgentStore()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore(policy: AttentionStore.Policy = .init()) -> AttentionStore {
        AttentionStore(
            policy: policy,
            persistence: AttentionPersistence(directory: tempDir),
            now: { self.virtualNow }
        )
    }

    private func wireAgentStore() {
        agentStore.transitions.sink { transition in
            guard let event = AgentAttentionMapper.event(for: transition) else { return }
            self.store.publish(event)
        }.store(in: &subscriptions)
        agentStore.resolutions.sink { resolution in
            self.store.resolve(dedupKey: AgentAttentionMapper.permissionDedupKey(
                sessionID: resolution.session.id, cycleID: resolution.cycleID
            ))
        }.store(in: &subscriptions)
    }

    private var eventCounter = 0
    private func ingest(
        _ name: String, provider: AgentProviderKind = .claude, session: String = "sess-A72F",
        cwd: String = "/tmp/projectx", tool: String? = nil, detail: String? = nil,
        notificationType: String? = nil, dedup: String? = nil
    ) {
        eventCounter += 1
        agentStore.ingest(AgentWireEvent(
            provider: provider, event: name, sessionID: session,
            timestamp: virtualNow.timeIntervalSince1970, cwd: cwd,
            toolName: tool, activityDetail: detail, notificationType: notificationType,
            dedupKey: dedup ?? "e\(eventCounter)"
        ))
    }

    private func advance(_ seconds: TimeInterval) {
        virtualNow = virtualNow.addingTimeInterval(seconds)
    }

    private var allItems: [AttentionItem] { store.sortedItems() }

    func testPermissionCreatesSingleUnresolvedHighItem() {
        ingest("UserPromptSubmit")
        ingest("PermissionRequest", tool: "Bash", detail: "rm x")
        ingest("Notification", notificationType: "permission_prompt")

        let items = allItems
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].kind, .needsPermission)
        XCTAssertEqual(items[0].priority, .high)
        XCTAssertFalse(items[0].isResolved)
        XCTAssertTrue(items[0].isUnread)
        XCTAssertEqual(store.highPriorityUnreadCount, 1)
        XCTAssertEqual(notified.count, 1)
    }

    func testPermissionResolutionOnContinuation() {
        ingest("UserPromptSubmit")
        ingest("PermissionRequest", tool: "Bash", detail: "rm x")
        ingest("PreToolUse", tool: "Bash", detail: "rm x")

        let item = allItems[0]
        XCTAssertTrue(item.isResolved)
        XCTAssertEqual(item.priority, .normal)
        XCTAssertEqual(store.highPriorityUnreadCount, 0)
        XCTAssertTrue(item.isUnread)
    }

    func testFinishedCreatesResolvedUnreadItemOncePerCycle() {
        ingest("UserPromptSubmit")
        advance(10)
        ingest("Stop", dedup: "stop-1")
        ingest("Stop", dedup: "stop-1")

        let finished = allItems.filter { $0.kind == .finished }
        XCTAssertEqual(finished.count, 1)
        XCTAssertTrue(finished[0].isResolved)
        XCTAssertTrue(finished[0].isUnread)
        XCTAssertTrue(finished[0].detail.hasPrefix("Finished in"))
        XCTAssertEqual(notified.count, 1)
    }

    func testTwoCyclesCreateTwoFinishedItems() {
        ingest("UserPromptSubmit")
        advance(10)
        ingest("Stop")
        ingest("UserPromptSubmit")
        advance(10)
        ingest("Stop")

        XCTAssertEqual(allItems.filter { $0.kind == .finished }.count, 2)
        XCTAssertEqual(notified.count, 2)
    }

    func testFailedCreatesHighUnreadItem() {
        ingest("UserPromptSubmit")
        advance(5)
        ingest("StopFailure", detail: "rate limit exceeded")

        let failed = allItems.filter { $0.kind == .failed }
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(failed[0].priority, .high)
        XCTAssertTrue(failed[0].isUnread)
        XCTAssertEqual(failed[0].detail, "rate limit")
    }

    func testPermissionThenStopResolvesAndCreatesFinished() {
        ingest("UserPromptSubmit")
        advance(5)
        ingest("PermissionRequest", tool: "Bash", detail: "x")
        ingest("Stop")

        let permission = allItems.first { $0.kind == .needsPermission }
        let finished = allItems.first { $0.kind == .finished }
        XCTAssertNotNil(finished)
        XCTAssertEqual(permission?.isResolved, true)
        XCTAssertEqual(store.highPriorityUnreadCount, 0)
    }

    func testSessionEndResolvesPendingPermission() {
        ingest("UserPromptSubmit")
        ingest("PermissionRequest", tool: "Bash", detail: "x")
        ingest("SessionEnd")

        XCTAssertEqual(allItems.first { $0.kind == .needsPermission }?.isResolved, true)
    }

    func testPermissionThenFailureResolvesPermissionAndCreatesFailure() {
        ingest("UserPromptSubmit")
        advance(5)
        ingest("PermissionRequest", tool: "Bash", detail: "x")
        ingest("StopFailure", detail: "boom")

        XCTAssertEqual(allItems.first { $0.kind == .needsPermission }?.isResolved, true)
        XCTAssertEqual(allItems.filter { $0.kind == .failed }.count, 1)
    }

    func testMultipleSessionsIndependentItems() {
        ingest("UserPromptSubmit", session: "a")
        ingest("PermissionRequest", session: "a", tool: "Bash", detail: "x")
        ingest("UserPromptSubmit", session: "b")
        advance(5)
        ingest("Stop", session: "b")
        ingest("UserPromptSubmit", provider: .codex, session: "c")
        advance(5)
        ingest("StopFailure", provider: .codex, session: "c", detail: "boom")

        XCTAssertEqual(allItems.count, 3)
        XCTAssertEqual(Set(allItems.map(\.relatedAgentSessionID)).count, 3)
    }

    func testSameProjectSessionsStayDistinct() {
        ingest("UserPromptSubmit", session: "AAAA", cwd: "/tmp/same")
        advance(5)
        ingest("Stop", session: "AAAA", cwd: "/tmp/same")
        ingest("UserPromptSubmit", session: "BBBB", cwd: "/tmp/same")
        advance(5)
        ingest("Stop", session: "BBBB", cwd: "/tmp/same")

        let items = allItems
        XCTAssertEqual(items.count, 2)
        XCTAssertNotEqual(items[0].sessionAlias, items[1].sessionAlias)
    }

    func testProviderIdentityPreserved() {
        ingest("UserPromptSubmit", provider: .codex, session: "x1")
        advance(5)
        ingest("Stop", provider: .codex, session: "x1")

        XCTAssertEqual(allItems[0].provider, .codex)
        XCTAssertEqual(allItems[0].title, "Codex")
        XCTAssertEqual(allItems[0].source, .agent(.codex))
    }

    func testSortingOrder() {
        ingest("UserPromptSubmit", session: "fin")
        advance(5)
        ingest("Stop", session: "fin")
        advance(5)
        ingest("UserPromptSubmit", session: "fail")
        advance(5)
        ingest("StopFailure", session: "fail", detail: "boom")
        advance(5)
        ingest("UserPromptSubmit", session: "perm")
        ingest("PermissionRequest", session: "perm", tool: "Bash", detail: "x")

        var kinds = allItems.map(\.kind)
        XCTAssertEqual(kinds, [.needsPermission, .failed, .finished])

        store.markRead(allItems.first { $0.kind == .failed }!.id)
        kinds = allItems.map(\.kind)
        XCTAssertEqual(kinds, [.needsPermission, .finished, .failed])
    }

    func testUnreadReadDismissDimensions() {
        ingest("UserPromptSubmit")
        advance(5)
        ingest("Stop")
        let id = allItems[0].id

        XCTAssertEqual(store.unreadCount, 1)
        store.markRead(id)
        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertEqual(allItems.count, 1)

        store.dismiss(id)
        XCTAssertTrue(allItems.isEmpty)
        XCTAssertEqual(store.items.count, 1)
    }

    func testClearReadKeepsUnread() {
        ingest("UserPromptSubmit", session: "a")
        advance(5)
        ingest("Stop", session: "a")
        ingest("UserPromptSubmit", session: "b")
        advance(5)
        ingest("Stop", session: "b")

        store.markRead(allItems[0].id)
        store.clearRead()

        XCTAssertEqual(allItems.count, 1)
        XCTAssertTrue(allItems[0].isUnread)
    }

    func testBadgeFormatter() {
        XCTAssertNil(AttentionBadgeFormatter.label(0))
        XCTAssertEqual(AttentionBadgeFormatter.label(1), "1")
        XCTAssertEqual(AttentionBadgeFormatter.label(9), "9")
        XCTAssertEqual(AttentionBadgeFormatter.label(10), "9+")
    }

    func testOneTransitionOneNotificationRequest() {
        ingest("UserPromptSubmit")
        ingest("PermissionRequest", tool: "Bash", detail: "x")
        ingest("Notification", notificationType: "permission_prompt")
        ingest("PreToolUse", tool: "Bash", detail: "x")
        advance(5)
        ingest("Stop", dedup: "s1")
        ingest("Stop", dedup: "s1")

        XCTAssertEqual(notified.count, 2)
        XCTAssertEqual(Set(notified.map(\.dedupKey)).count, 2)
    }

    func testNotificationManagerDedupsByItemKey() {
        final class RecordingPoster: AgentNotificationPosting {
            var posted: [String] = []
            func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(true) }
            func post(title: String, subtitle: String, body: String, thread: String, identifier: String) {
                posted.append(identifier)
            }
        }
        let poster = RecordingPoster()
        let manager = AgentNotificationManager(poster: poster)
        ingest("UserPromptSubmit")
        advance(5)
        ingest("Stop")
        let item = allItems[0]
        manager.post(item: item)
        manager.post(item: item)
        XCTAssertEqual(poster.posted.count, 1)
        XCTAssertEqual(poster.posted[0], item.dedupKey)
    }

    func testPersistenceRoundtripPreservesStateAndDedup() {
        ingest("UserPromptSubmit", session: "a")
        ingest("PermissionRequest", session: "a", tool: "Bash", detail: "x")
        ingest("UserPromptSubmit", session: "b")
        advance(5)
        ingest("Stop", session: "b")
        store.markRead(allItems.first { $0.kind == .finished }!.id)
        store.persistNow()

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.items.count, 2)
        XCTAssertEqual(reloaded.unreadCount, 1)
        XCTAssertEqual(reloaded.highPriorityUnreadCount, 1)

        var reloadedNotified = 0
        var subs = Set<AnyCancellable>()
        reloaded.notificationRequests.sink { _ in reloadedNotified += 1 }.store(in: &subs)
        let finishedItem = reloaded.sortedItems().first { $0.kind == .finished }!
        reloaded.publish(AttentionEvent(
            dedupKey: finishedItem.dedupKey, source: finishedItem.source,
            kind: finishedItem.kind, priority: finishedItem.priority,
            title: finishedItem.title, subtitle: finishedItem.subtitle,
            detail: finishedItem.detail, provider: finishedItem.provider,
            projectName: finishedItem.projectName, projectPath: finishedItem.projectPath,
            sessionAlias: finishedItem.sessionAlias,
            relatedAgentSessionID: finishedItem.relatedAgentSessionID,
            relatedWorkCycleID: finishedItem.relatedWorkCycleID
        ))
        XCTAssertEqual(reloadedNotified, 0)
        XCTAssertEqual(reloaded.items.count, 2)
    }

    func testCorruptedPersistenceRecovers() {
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let file = tempDir.appendingPathComponent("attention.json")
        try? Data("not json at all {{{".utf8).write(to: file)

        let recovered = makeStore()
        XCTAssertTrue(recovered.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
        XCTAssertTrue(entries.contains { $0.hasPrefix("attention.corrupted-") })
    }

    func testRetentionAgeAndBoundsProtectUnresolvedHigh() {
        ingest("UserPromptSubmit", session: "old")
        advance(5)
        ingest("Stop", session: "old")
        ingest("UserPromptSubmit", session: "perm")
        ingest("PermissionRequest", session: "perm", tool: "Bash", detail: "x")

        advance(8 * 24 * 3600)
        ingest("UserPromptSubmit", session: "fresh")
        advance(5)
        ingest("Stop", session: "fresh")

        let items = allItems
        XCTAssertNil(items.first { $0.relatedAgentSessionID.contains("old") })
        XCTAssertNotNil(items.first { $0.kind == .needsPermission })
        XCTAssertNotNil(items.first { $0.relatedAgentSessionID.contains("fresh") })
    }

    func testRetentionMaxItemsKeepsNewest() {
        let small = makeStore(policy: .init(maxItems: 3))
        for index in 0..<6 {
            small.publish(AttentionEvent(
                dedupKey: "k\(index)", source: .agent(.claude), kind: .finished,
                priority: .normal, title: "Claude Code", subtitle: "p · C-000\(index)",
                detail: "Finished", provider: .claude, projectName: "p", projectPath: nil,
                sessionAlias: "C-000\(index)", relatedAgentSessionID: "claude:s\(index)",
                relatedWorkCycleID: 1
            ))
            advance(60)
        }
        XCTAssertEqual(small.items.count, 3)
        XCTAssertNotNil(small.items["k5"])
        XCTAssertNil(small.items["k0"])
    }

    func testCompactSurfacePlan() {
        var plan = CompactSurfacePlan.plan(hasMedia: false, hasAgentSummary: false, highPriorityCount: 0)
        XCTAssertTrue(plan.isEmpty)

        plan = CompactSurfacePlan.plan(hasMedia: true, hasAgentSummary: false, highPriorityCount: 0)
        XCTAssertTrue(plan.showsMedia)
        XCTAssertFalse(plan.showsMicroCluster)

        plan = CompactSurfacePlan.plan(hasMedia: true, hasAgentSummary: false, highPriorityCount: 2)
        XCTAssertTrue(plan.showsMedia)
        XCTAssertTrue(plan.showsMicroCluster)
        XCTAssertTrue(plan.showsAttentionBadge)

        plan = CompactSurfacePlan.plan(hasMedia: false, hasAgentSummary: false, highPriorityCount: 1)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(plan.showsAttentionBadge)

        plan = CompactSurfacePlan.plan(hasMedia: false, hasAgentSummary: true, highPriorityCount: 0)
        XCTAssertTrue(plan.showsAgentSummary)
    }

    func testProjectPathFlowsIntoAttentionItem() {
        ingest("UserPromptSubmit", cwd: "/tmp/some-missing-dir/projecty")
        advance(5)
        ingest("Stop")
        XCTAssertEqual(allItems[0].projectPath, "/tmp/some-missing-dir/projecty")
        XCTAssertEqual(allItems[0].projectName, "projecty")
    }
}
