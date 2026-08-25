import XCTest
@testable import PersonalIsland

final class AgentActivityFormatterTests: XCTestCase {
    func testToolPhrasing() {
        XCTAssertEqual(
            AgentActivityFormatter.activity(toolName: "Read", detail: "/a/b/IslandWindowController.swift"),
            "Reading IslandWindowController.swift"
        )
        XCTAssertEqual(
            AgentActivityFormatter.activity(toolName: "Edit", detail: "/x/ScreenshotBuffer.swift"),
            "Editing ScreenshotBuffer.swift"
        )
        XCTAssertEqual(
            AgentActivityFormatter.activity(toolName: "Write", detail: "New.swift"),
            "Writing New.swift"
        )
        XCTAssertEqual(
            AgentActivityFormatter.activity(toolName: "Bash", detail: "xcodebuild test"),
            "Running xcodebuild test"
        )
        XCTAssertEqual(AgentActivityFormatter.activity(toolName: "Grep", detail: "foo"), "Searching")
        XCTAssertEqual(
            AgentActivityFormatter.activity(toolName: "mcp__github__create_issue", detail: nil),
            "Using MCP tool"
        )
        XCTAssertEqual(AgentActivityFormatter.activity(toolName: nil, detail: nil), "Working")
    }

    func testLongCommandTruncation() {
        let long = String(repeating: "x", count: 300)
        let line = AgentActivityFormatter.activity(toolName: "Bash", detail: long)
        XCTAssertLessThanOrEqual(line.count, AgentActivityFormatter.maxLength + 1)
    }

    func testSecretRedactionInMapper() {
        let redacted = AgentHookPayloadMapper.redactSecrets(
            in: "curl -H 'Authorization: Bearer abc.def' TOKEN=supersecret PASSWORD=hunter2"
        )
        XCTAssertFalse(redacted.contains("abc.def"))
        XCTAssertFalse(redacted.contains("supersecret"))
        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertTrue(redacted.contains("•••"))
    }

    func testMapperBuildsDeterministicDedupKey() {
        let payload: [String: Any] = [
            "hook_event_name": "PreToolUse", "session_id": "s1",
            "tool_name": "Bash", "tool_input": ["command": "ls"], "cwd": "/tmp",
        ]
        let one = AgentHookPayloadMapper.wireEvent(
            provider: .claude, payload: payload, invocationToken: "pid-1"
        )
        let sameInvocation = AgentHookPayloadMapper.wireEvent(
            provider: .claude, payload: payload, invocationToken: "pid-1"
        )
        XCTAssertEqual(one?.dedupKey, sameInvocation?.dedupKey, "one invocation keeps one identity")

        let laterInvocation = AgentHookPayloadMapper.wireEvent(
            provider: .claude, payload: payload, invocationToken: "pid-2"
        )
        XCTAssertNotEqual(
            one?.dedupKey, laterInvocation?.dedupKey,
            "a repeated hook event is a distinct event, not a duplicate"
        )

        let first = AgentHookPayloadMapper.defaultInvocationToken(
            pid: 42, now: Date(timeIntervalSince1970: 100)
        )
        let second = AgentHookPayloadMapper.defaultInvocationToken(
            pid: 42, now: Date(timeIntervalSince1970: 100.5)
        )
        XCTAssertNotEqual(first, second)

        XCTAssertEqual(one?.activityDetail, "ls")
        XCTAssertNil(AgentHookPayloadMapper.wireEvent(provider: .claude, payload: ["foo": 1]))
    }

    func testFailureCategories() {
        XCTAssertEqual(AgentActivityFormatter.failureCategory("Rate limit exceeded"), "rate limit")
        XCTAssertEqual(AgentActivityFormatter.failureCategory("authentication_error"), "authentication")
        XCTAssertEqual(AgentActivityFormatter.failureCategory("weird"), "error")
    }
}

@MainActor
final class AgentNotificationManagerTests: XCTestCase {
    final class SpyPoster: AgentNotificationPosting {
        var posted: [(title: String, subtitle: String, body: String, thread: String)] = []
        func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(true) }
        func post(title: String, subtitle: String, body: String, thread: String, identifier: String) {
            posted.append((title, subtitle, body, thread))
        }
    }

    func testNotificationIdentityAndDedup() {
        let poster = SpyPoster()
        let manager = AgentNotificationManager(poster: poster)
        var session = AgentSession(
            provider: .claude, sessionID: "abcd-A72F", project: "PersonalIsland",
            branch: nil, startedAt: Date(), lastActivityAt: Date()
        )
        session.lastCycleDuration = 514
        let transition = AgentTransition(session: session, kind: .finished, dedupKey: "t1")

        manager.handle(transition)
        manager.handle(transition)
        XCTAssertEqual(poster.posted.count, 1)
        XCTAssertEqual(poster.posted[0].title, "Claude Code · PersonalIsland")
        XCTAssertEqual(poster.posted[0].subtitle, "C-A72F · Finished")
        XCTAssertEqual(poster.posted[0].body, "Finished in 8:34")
        XCTAssertEqual(poster.posted[0].thread, "claude:abcd-A72F")
    }

    func testCodexNotificationSaysCodex() {
        let poster = SpyPoster()
        let manager = AgentNotificationManager(poster: poster)
        var session = AgentSession(
            provider: .codex, sessionID: "thr_92C1", project: "backend",
            branch: nil, startedAt: Date(), lastActivityAt: Date()
        )
        session.activity = "Running xcodebuild test"
        manager.handle(AgentTransition(session: session, kind: .needsPermission, dedupKey: "t2"))
        XCTAssertEqual(poster.posted[0].title, "Codex · backend")
        XCTAssertEqual(poster.posted[0].subtitle, "X-92C1 · Needs permission")
        XCTAssertTrue(poster.posted[0].body.contains("xcodebuild test"))
    }
}

final class AgentSpoolTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agent-spool-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeEvent(_ name: String, dedup: String) {
        let event = AgentWireEvent(
            provider: .claude, event: name, sessionID: "s", timestamp: 1,
            cwd: nil, toolName: nil, activityDetail: nil, notificationType: nil, dedupKey: dedup
        )
        let data = try! JSONEncoder().encode(event)
        try! data.write(to: directory.appendingPathComponent("\(dedup).json"))
    }

    func testReplayDeliversDecodesAndDeletes() {
        writeEvent("Stop", dedup: "aaa")
        writeEvent("SessionStart", dedup: "bbb")
        try! Data("garbage".utf8).write(to: directory.appendingPathComponent("zzz.json"))

        var delivered: [Data] = []
        let replayed = AgentEventReceiver.consumeSpool(directory: directory) { delivered.append($0) }
        XCTAssertEqual(replayed, 3, "delivery is attempted; decoding filters garbage downstream")
        XCTAssertEqual(delivered.count, 3)
        let remaining = try! FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(remaining.isEmpty, "consumed spool files are deleted")
    }

    func testCountBoundEnforced() {
        for index in 0..<10 { writeEvent("Stop", dedup: "k\(index)") }
        var count = 0
        AgentEventReceiver.consumeSpool(directory: directory, maxEvents: 4) { _ in count += 1 }
        XCTAssertEqual(count, 4)
        let remaining = try! FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(remaining.isEmpty, "excess files are still cleaned up")
    }
}

final class AgentHookInstallerTests: XCTestCase {
    private var directory: URL!
    private var installer: AgentHookInstaller!

    override func setUp() {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hook-cfg-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        installer = AgentHookInstaller(
            claudeSettingsURL: directory.appendingPathComponent("settings.json"),
            codexHooksURL: directory.appendingPathComponent("hooks.json"),
            helperURL: directory.appendingPathComponent("bin/personal-island-agent-hook"),
            backupsDirectory: directory.appendingPathComponent("backups")
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func loadJSON(_ url: URL) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
    }

    func testMergePreservesForeignConfigAndIsIdempotent() throws {
        let existing: [String: Any] = [
            "model": "claude-fable-5",
            "customKey": ["nested": true],
            "hooks": [
                "PreToolUse": [
                    ["matcher": "*", "hooks": [["type": "command", "command": "/foreign/gateguard.sh"]]],
                ],
            ],
        ]
        let url = installer.claudeSettingsURL
        try JSONSerialization.data(withJSONObject: existing).write(to: url)

        try installer.installClaudeHooks()
        try installer.installClaudeHooks()

        let merged = loadJSON(url)
        XCTAssertEqual(merged["model"] as? String, "claude-fable-5", "unknown fields preserved")
        XCTAssertNotNil(merged["customKey"])
        let hooks = merged["hooks"] as! [String: Any]
        let preToolUse = hooks["PreToolUse"] as! [[String: Any]]
        XCTAssertEqual(preToolUse.count, 2, "foreign hook + exactly ONE of ours")
        let commands = preToolUse.flatMap { ($0["hooks"] as! [[String: Any]]).compactMap { $0["command"] as? String } }
        XCTAssertTrue(commands.contains { $0.contains("gateguard") }, "foreign hook preserved")
        XCTAssertEqual(commands.filter { $0.contains("personal-island-agent-hook") }.count, 1)

        for event in AgentHookInstaller.claudeEvents {
            XCTAssertNotNil(hooks[event], "missing \(event)")
        }

        let backups = try FileManager.default.contentsOfDirectory(atPath: installer.backupsDirectory.path)
        XCTAssertFalse(backups.isEmpty)
    }

    func testUninstallRemovesOnlyOurEntries() throws {
        let existing: [String: Any] = [
            "hooks": [
                "Stop": [["matcher": "*", "hooks": [["type": "command", "command": "/foreign/x.sh"]]]],
            ],
        ]
        try JSONSerialization.data(withJSONObject: existing).write(to: installer.claudeSettingsURL)
        try installer.installClaudeHooks()
        try installer.uninstall(configURL: installer.claudeSettingsURL)

        let hooks = loadJSON(installer.claudeSettingsURL)["hooks"] as! [String: Any]
        let stop = hooks["Stop"] as! [[String: Any]]
        XCTAssertEqual(stop.count, 1)
        let command = (stop[0]["hooks"] as! [[String: Any]])[0]["command"] as! String
        XCTAssertTrue(command.contains("/foreign/x.sh"))
        for event in AgentHookInstaller.claudeEvents where event != "Stop" {
            XCTAssertNil(hooks[event], "our-only event arrays removed on uninstall")
        }
    }

    func testInvalidExistingConfigIsRefusedUntouched() throws {
        let url = installer.claudeSettingsURL
        try Data("{broken json".utf8).write(to: url)
        XCTAssertThrowsError(try installer.installClaudeHooks())
        XCTAssertEqual(String(data: try Data(contentsOf: url), encoding: .utf8), "{broken json")
    }

    func testCodexInstallCreatesHooksDocument() throws {
        try installer.installCodexHooks()
        let document = loadJSON(installer.codexHooksURL)
        let hooks = document["hooks"] as! [String: Any]
        for event in AgentHookInstaller.codexEvents {
            XCTAssertNotNil(hooks[event])
        }
        XCTAssertNil(hooks["StopFailure"], "codex does not support StopFailure")
        let group = (hooks["Stop"] as! [[String: Any]])[0]
        let command = ((group["hooks"] as! [[String: Any]])[0]["command"] as? String) ?? ""
        XCTAssertTrue(command.contains("--provider codex"))
    }
}

@MainActor
final class AgentProviderIconResolverTests: XCTestCase {
    func testResolvesInstalledOfficialIconsAndCaches() {
        let resolver = AgentProviderIconResolver.shared
        let first = resolver.icon(for: .claude)
        let second = resolver.icon(for: .claude)

        XCTAssertNotNil(first)
        XCTAssertTrue(first === second, "cached NSImage instance")
        XCTAssertNotNil(resolver.icon(for: .codex), "ChatGPT.app (com.openai.codex) installed")
    }
}
