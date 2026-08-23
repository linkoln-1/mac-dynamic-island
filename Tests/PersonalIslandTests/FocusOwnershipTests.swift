import XCTest
import SwiftUI
@testable import PersonalIsland

private final class KeyableHostPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class FocusOwnershipTests: XCTestCase {
    private var host: NSPanel!
    private var field: NSTextField!
    private var state: IslandState!
    private var controller: IslandWindowController!

    override func setUp() async throws {
        field = NSTextField(frame: NSRect(x: 20, y: 20, width: 200, height: 24))
        host = KeyableHostPanel(
            contentRect: NSRect(x: 200, y: 300, width: 300, height: 80),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        host.contentView?.addSubview(field)
        host.makeKeyAndOrderFront(nil)
        host.makeFirstResponder(field)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try XCTSkipIf(!host.isKeyWindow, "host window could not become key in this environment")

        state = IslandState()
        controller = IslandWindowController(state: state)
        controller.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try XCTSkipIf(controller.panel == nil, "no screen available")
    }

    override func tearDown() async throws {
        state?.dismissExpanded()
        controller?.panel?.orderOut(nil)
        host?.orderOut(nil)
    }

    private func settle(_ seconds: TimeInterval = 0.3) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func clickIsland(x: CGFloat, yTop: CGFloat) {
        guard let panel = controller.panel else { return }
        let point = NSPoint(x: x, y: IslandMetrics.windowSize.height - yTop)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) else { continue }
            NSApp.sendEvent(event)
        }
        settle(0.2)
    }

    private func typeKey(_ characters: String, keyCode: UInt16) {
        guard let window = NSApp.keyWindow else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: keyCode
            ) else { continue }
            NSApp.sendEvent(event)
        }
    }

    func testExpandKeepsHostWindowKey() {
        state.expand()
        settle(0.5)
        XCTAssertTrue(host.isKeyWindow, "expanding the island must not take key status")
        XCTAssertNotEqual(NSApp.keyWindow, controller.panel)
        XCTAssertEqual(controller.panel?.isKeyWindow, false)
    }

    func testModuleClicksWorkWithoutTakingKeyStatus() {
        state.expand()
        settle(0.5)
        clickIsland(x: 43, yTop: 64)
        XCTAssertEqual(state.selectedModuleID, "screenshots")
        XCTAssertTrue(host.isKeyWindow, "clicking a module button must not steal key")

        clickIsland(x: 43, yTop: 104)
        XCTAssertEqual(state.selectedModuleID, "nowPlaying")
        XCTAssertTrue(host.isKeyWindow)
    }

    func testTypingAfterIslandInteractionReachesHostField() {
        state.expand()
        settle(0.5)
        clickIsland(x: 43, yTop: 64)
        XCTAssertTrue(host.isKeyWindow)
        host.makeFirstResponder(field)

        for character in "abc123" {
            typeKey(String(character), keyCode: 0)
        }
        settle(0.2)
        let text = (field.currentEditor()?.string ?? field.stringValue)
        XCTAssertTrue(text.contains("abc123"),
                      "typed text must reach the host field, got: '\(text)'")
    }

    func testKeyboardNeverDrivesModuleSwitching() {
        state.expand()
        settle(0.5)
        state.select(moduleID: "screenshots")

        typeKey(" ", keyCode: 49)
        typeKey("\t", keyCode: 48)
        typeKey("x", keyCode: 7)
        typeKey("5", keyCode: 23)
        settle(0.3)

        XCTAssertEqual(state.selectedModuleID, "screenshots",
                       "keyboard input must never activate island buttons")
        XCTAssertTrue(host.isKeyWindow)
    }

    func testPanelCanNeverBecomeKey() {
        guard let panel = controller.panel else { return XCTFail("no panel") }
        XCTAssertFalse(panel.canBecomeKey)
        panel.makeKey()
        settle(0.1)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(host.isKeyWindow)
    }
}
