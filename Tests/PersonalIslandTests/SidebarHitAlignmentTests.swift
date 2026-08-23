import XCTest
import SwiftUI
@testable import PersonalIsland

@MainActor
final class SidebarHitAlignmentTests: XCTestCase {
    private var state: IslandState!
    private var controller: IslandWindowController!

    override func setUp() async throws {
        state = IslandState()
        controller = IslandWindowController(state: state)
        controller.start()
        state.expand()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        try XCTSkipIf(controller.panel == nil, "no screen available")
    }

    override func tearDown() async throws {
        state.dismissExpanded()
        controller.panel?.orderOut(nil)
    }

    private var buttonColumnX: CGFloat {
        IslandMetrics.expandedContentHorizontalInset + IslandMetrics.sidebarWidth / 2
    }

    private func buttonTop(index: Int) -> CGFloat {
        state.closedSize.height + 6 + CGFloat(index) * IslandMetrics.sidebarButtonHitTarget
    }

    private func buttonCenterY(index: Int) -> CGFloat {
        buttonTop(index: index) + IslandMetrics.sidebarButtonHitTarget / 2
    }

    @discardableResult
    private func click(x: CGFloat, yTop: CGFloat) -> String? {
        let sentinel = "___probe___"
        state.select(moduleID: sentinel)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        guard let window = controller.panel else { return nil }
        let point = NSPoint(x: x, y: IslandMetrics.windowSize.height - yTop)
        for (type, _) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 1)] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) else { continue }
            NSApp.sendEvent(event)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        return state.selectedModuleID == sentinel ? nil : state.selectedModuleID
    }

    private func clickWithRetry(x: CGFloat, yTop: CGFloat, attempts: Int = 3) -> String? {
        for _ in 0..<attempts {
            if let hit = click(x: x, yTop: yTop) { return hit }
        }
        return nil
    }

    func testScreenshotButtonClickableAtCenterAndEdges() {
        let x = buttonColumnX
        XCTAssertEqual(clickWithRetry(x: x, yTop: buttonCenterY(index: 0)), "screenshots",
                       "center of the visible Screenshot button must switch modules")
        XCTAssertEqual(clickWithRetry(x: x, yTop: buttonTop(index: 0) + 3), "screenshots",
                       "top edge inside the button frame must hit")
        XCTAssertEqual(clickWithRetry(x: x, yTop: buttonTop(index: 0) + 37), "screenshots",
                       "bottom edge inside the button frame must hit")
        XCTAssertEqual(clickWithRetry(x: x - 17, yTop: buttonCenterY(index: 0)), "screenshots",
                       "left edge inside the button frame must hit")
    }

    func testMusicButtonClickableAtCenter() {
        XCTAssertEqual(clickWithRetry(x: buttonColumnX, yTop: buttonCenterY(index: 1)), "nowPlaying",
                       "center of the visible Now Playing button must switch modules")
    }

    func testNoGhostClickAreaAboveButtons() {

        XCTAssertNil(click(x: buttonColumnX, yTop: 20),
                     "notch strip above the sidebar must not be a module target")
        XCTAssertNil(click(x: buttonColumnX, yTop: buttonTop(index: 0) - 4),
                     "the gap just above the first button must not switch modules")
    }

    func testNoFalseHitOutsideSidebarColumn() {

        XCTAssertNil(click(x: 8, yTop: buttonCenterY(index: 0)),
                     "island edge outside the sidebar must not switch modules")
    }

    func testHitFramesRespectExpandedSidebarInset() {

        XCTAssertGreaterThanOrEqual(
            buttonColumnX - IslandMetrics.sidebarButtonHitTarget / 2,
            IslandMetrics.expandedTopRadius
        )
        XCTAssertEqual(buttonTop(index: 1), buttonTop(index: 0) + IslandMetrics.sidebarButtonHitTarget)
    }
}
