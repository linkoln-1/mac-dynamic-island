import Combine
import XCTest
@testable import PersonalIsland

@MainActor
final class AgentStoreTests: XCTestCase {
    private var virtualNow = Date(timeIntervalSince1970: 50_000)
    private var store: AgentStore!
    private var received: [AgentTransition] = []
    private var transitionSubscription: AnyCancellable?

    override func setUp() {
        virtualNow = Date(timeIntervalSince1970: 50_000)
        store = AgentStore(
            policy: .init(finishedRetention: 1500, staleThreshold: 1800, minimumNotifiedCycle: 3),
            now: { self.virtualNow }
        )
        received = []
        transitionSubscription = store.transitions.sink { self.received.append($0) }
    }

    private func advance(_ seconds: TimeInterval) {
        virtualNow = virtualNow.addingTimeInterval(seconds)
    }

    private var eventCounter = 0
    private func event(
        _ name: String, provider: AgentProviderKind = .claude, session: String = "aaaa-bbbb-cccc-A72F",
        cwd: String = "/tmp/projectx", tool: String? = nil, detail: String? = nil,
        notificationType: String? = nil, dedup: String? = nil
    ) -> AgentWireEvent {
        eventCounter += 1
        return AgentWireEvent(
            provider: provider, event: name, sessionID: session,
            timestamp: virtualNow.timeIntervalSince1970, cwd: cwd,
            toolName: tool, activityDetail: detail, notificationType: notificationType,
            dedupKey: dedup ?? "k\(eventCounter)"
        )
    }

    private var session: AgentSession? { store.orderedSessions.first }

    func testLifecycleStateMachine() {
        store.ingest(event("SessionStart"))
        XCTAssertEqual(session?.state, .idle)

        store.ingest(event("UserPromptSubmit"))
        XCTAssertEqual(session?.state, .working)

        store.ingest(event("PreToolUse", tool: "Bash", detail: "xcodebuild test"))
        XCTAssertEqual(session?.state, .working)
        XCTAssertEqual(session?.activity, "Running xcodebuild test")

        store.ingest(event("PermissionRequest", tool: "Bash", detail: "git status"))
        XCTAssertEqual(session?.state, .needsPermission)

        store.ingest(event("PreToolUse", tool: "Bash", detail: "git status"))
        XCTAssertEqual(session?.state, .working, "continuation after permission")

        advance(10)
        store.ingest(event("Stop"))
        XCTAssertEqual(session?.state, .finished)
        XCTAssertEqual(session!.lastCycleDuration!, 10, accuracy: 0.5)

        store.ingest(event("UserPromptSubmit"))
        XCTAssertEqual(session?.state, .working, "new prompt starts a new cycle")
        XCTAssertEqual(session?.cycleID, 2)

        store.ingest(event("StopFailure", detail: "rate limit exceeded"))
        XCTAssertEqual(session?.state, .failed)
        XCTAssertEqual(session?.failureReason, "rate limit")
    }

    func testSubagentCounting() {
        store.ingest(event("UserPromptSubmit"))
        store.ingest(event("SubagentStart"))
        store.ingest(event("SubagentStart"))
        XCTAssertEqual(session?.subagentCount, 2)
        store.ingest(event("SubagentStop"))
        XCTAssertEqual(session?.subagentCount, 1)
        store.ingest(event("Stop"))
        XCTAssertEqual(session?.subagentCount, 0)
    }

    func testTwoClaudeSessionsSameCwdStaySeparate() {
        store.ingest(event("UserPromptSubmit", session: "s-one"))
        store.ingest(event("UserPromptSubmit", session: "s-two"))
        XCTAssertEqual(store.sessions.count, 2)
    }

    func testClaudeAndCodexSameCwdAndIDStaySeparate() {
        store.ingest(event("UserPromptSubmit", provider: .claude, session: "same-id"))
        store.ingest(event("UserPromptSubmit", provider: .codex, session: "same-id"))
        XCTAssertEqual(store.sessions.count, 2)

        store.ingest(event("Stop", provider: .claude, session: "same-id"))
        let codex = store.sessions["codex:same-id"]
        XCTAssertEqual(codex?.state, .working, "Claude Stop must not touch the Codex card")
    }

    func testAliasIsShortDeterministicAndProviderSpecific() {
        store.ingest(event("SessionStart", provider: .claude, session: "aaaa-bbbb-cccc-A72F"))
        store.ingest(event("SessionStart", provider: .codex, session: "thr_92c1"))
        let aliases = Set(store.sessions.values.map(\.alias))
        XCTAssertEqual(aliases, ["C-A72F", "X-92C1"])
        for alias in aliases {
            XCTAssertLessThanOrEqual(alias.count, 6, "no full UUID exposure")
        }
    }

    func testImportantTransitionsNotifyOnceEach() {
        store.ingest(event("UserPromptSubmit"))
        advance(5)
        store.ingest(event("PermissionRequest", tool: "Bash", detail: "rm x"))
        XCTAssertEqual(received.map(\.kind), [.needsPermission])

        store.ingest(event("Notification", notificationType: "permission_prompt"))
        XCTAssertEqual(received.count, 1)

        store.ingest(event("PreToolUse", tool: "Bash", detail: "rm x"))
        advance(5)
        store.ingest(event("Stop"))
        XCTAssertEqual(received.map(\.kind), [.needsPermission, .finished])
    }

    func testNoisyEventsDoNotNotify() {
        store.ingest(event("SessionStart"))
        store.ingest(event("UserPromptSubmit"))
        store.ingest(event("PreToolUse", tool: "Read", detail: "a.swift"))
        store.ingest(event("PreToolUse", tool: "Edit", detail: "b.swift"))
        store.ingest(event("SubagentStart"))
        store.ingest(event("SubagentStop"))
        XCTAssertTrue(received.isEmpty, "tool events must never notify (§77)")
    }

    func testDuplicateAndReplayedEventsAreIgnored() {
        store.ingest(event("UserPromptSubmit", dedup: "fixed-1"))
        advance(5)
        store.ingest(event("Stop", dedup: "fixed-2"))
        store.ingest(event("Stop", dedup: "fixed-2"))
        XCTAssertEqual(received.map(\.kind), [.finished])
        XCTAssertEqual(session?.cycleID, 1)
    }

    func testSeparateCyclesNotifySeparately() {
        store.ingest(event("UserPromptSubmit"))
        advance(5)
        store.ingest(event("Stop"))
        store.ingest(event("UserPromptSubmit"))
        advance(5)
        store.ingest(event("Stop"))
        XCTAssertEqual(received.filter { $0.kind == .finished }.count, 2, "different turns are not deduped (§119)")
        XCTAssertNotEqual(received[0].dedupKey, received[1].dedupKey)
    }

    func testVeryShortCycleDoesNotNotify() {
        store.ingest(event("UserPromptSubmit"))
        advance(1)
        store.ingest(event("Stop"))
        XCTAssertTrue(received.isEmpty)
        XCTAssertEqual(session?.state, .finished, "state still updates")
    }

    func testFinishedCardIsRetainedThenExpires() {
        store.ingest(event("UserPromptSubmit"))
        advance(10)
        store.ingest(event("Stop"))
        advance(600)
        store.sweep()
        XCTAssertEqual(store.sessions.count, 1, "recent finished stays visible")
        advance(1200)
        store.sweep()
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testFinishedCardAutoClearsInAboutAMinuteWithDefaultPolicy() {
        let defaultStore = AgentStore(now: { self.virtualNow })
        defaultStore.ingest(event("UserPromptSubmit"))
        advance(10)
        defaultStore.ingest(event("Stop"))
        advance(30)
        defaultStore.sweep()
        XCTAssertEqual(defaultStore.sessions.count, 1, "finished card visible within the first minute")
        advance(40)
        defaultStore.sweep()
        XCTAssertTrue(defaultStore.sessions.isEmpty, "finished card auto-clears after ~60s")
    }

    func testLiveIdleSessionSurvivesFinishedRetentionButEndedDoesNot() {
        let defaultStore = AgentStore(now: { self.virtualNow })
        defaultStore.ingest(event("SessionStart", session: "live"))
        defaultStore.ingest(event("SessionStart", session: "dead"))
        defaultStore.ingest(event("SessionEnd", session: "dead"))
        advance(120)
        defaultStore.sweep()
        XCTAssertNotNil(defaultStore.sessions["claude:live"], "live idle session must not be swept early")
        XCTAssertNil(defaultStore.sessions["claude:dead"], "ended session clears fast")
        advance(25 * 60)
        defaultStore.sweep()
        XCTAssertTrue(defaultStore.sessions.isEmpty)
    }

    func testClearInactiveKeepsOnlyActiveSessions() {
        store.ingest(event("UserPromptSubmit", session: "w1"))
        store.ingest(event("PermissionRequest", session: "p1", tool: "Bash"))
        store.ingest(event("UserPromptSubmit", session: "f1"))
        advance(5)
        store.ingest(event("Stop", session: "f1"))
        store.ingest(event("UserPromptSubmit", session: "x1"))
        store.ingest(event("StopFailure", session: "x1", detail: "boom"))
        store.ingest(event("SessionStart", session: "i1"))
        XCTAssertTrue(store.hasInactiveSessions())

        store.clearInactive()

        XCTAssertEqual(Set(store.sessions.keys), ["claude:w1", "claude:p1"],
                       "working and needs-permission survive; finished/failed/idle cleared")
        XCTAssertFalse(store.hasInactiveSessions())
    }

    func testOrderedSessionsFilteredByProvider() {
        store.ingest(event("UserPromptSubmit", provider: .claude, session: "c1"))
        store.ingest(event("UserPromptSubmit", provider: .codex, session: "x1"))
        store.ingest(event("SessionStart", provider: .codex, session: "x2"))

        XCTAssertEqual(store.orderedSessions(provider: nil).count, 3)
        XCTAssertEqual(store.orderedSessions(provider: .claude).map(\.id), ["claude:c1"])
        XCTAssertEqual(Set(store.orderedSessions(provider: .codex).map(\.id)), ["codex:x1", "codex:x2"])
        XCTAssertEqual(store.sessionCount(provider: nil), 3)
        XCTAssertEqual(store.sessionCount(provider: .claude), 1)
        XCTAssertEqual(store.sessionCount(provider: .codex), 2)
    }

    func testClearInactiveScopedToProvider() {
        store.ingest(event("UserPromptSubmit", provider: .claude, session: "c1"))
        advance(5)
        store.ingest(event("Stop", provider: .claude, session: "c1"))
        store.ingest(event("UserPromptSubmit", provider: .codex, session: "x1"))
        advance(5)
        store.ingest(event("Stop", provider: .codex, session: "x1"))
        store.ingest(event("UserPromptSubmit", provider: .codex, session: "x2"))

        XCTAssertTrue(store.hasInactiveSessions(provider: .claude))
        store.clearInactive(provider: .claude)

        XCTAssertEqual(Set(store.sessions.keys), ["codex:x1", "codex:x2"],
                       "clearing the Claude tab must not touch Codex cards")
        XCTAssertFalse(store.hasInactiveSessions(provider: .claude))
        XCTAssertTrue(store.hasInactiveSessions(provider: .codex))
    }

    func testWorkingSessionNeverExpiresButGoesStale() {
        store.ingest(event("UserPromptSubmit"))
        advance(2000)
        store.sweep()
        XCTAssertEqual(session?.state, .stale, "silent working session → stale, NEVER finished")
        XCTAssertEqual(received.filter { $0.kind == .finished }.count, 0)
    }

    func testCompactSummaryCounts() {
        store.ingest(event("UserPromptSubmit", session: "c1"))
        store.ingest(event("UserPromptSubmit", session: "c2"))
        store.ingest(event("PermissionRequest", session: "c3", tool: "Bash"))
        store.ingest(event("UserPromptSubmit", provider: .codex, session: "x1"))
        advance(5)
        store.ingest(event("Stop", provider: .codex, session: "x1"))

        let summary = store.compactSummary
        XCTAssertEqual(summary.claudeActive, 3)
        XCTAssertEqual(summary.codexActive, 0, "finished codex not active")
        XCTAssertEqual(summary.working, 2)
        XCTAssertEqual(summary.attention, 1)
    }

    func testProjectFallsBackToCwdBasename() {
        store.ingest(event("SessionStart", cwd: "/tmp/nonexistent-dir/my-project"))
        XCTAssertEqual(session?.project, "my-project")
    }
}
