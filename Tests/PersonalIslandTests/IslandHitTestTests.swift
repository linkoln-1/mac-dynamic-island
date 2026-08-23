import XCTest
@testable import PersonalIsland

@MainActor
final class IslandHitTestTests: XCTestCase {
    private let bounds = CGRect(origin: .zero, size: IslandMetrics.windowSize)
    private let closedSize = CGSize(width: 224, height: 38)

    func testCollapsedRectHugsTopCenterAndExcludesPanelCorners() {
        let rect = IslandHitTest.interactiveRect(mode: .collapsed, closedSize: closedSize, bounds: bounds)

        XCTAssertEqual(rect.midX, bounds.midX, accuracy: 0.5)
        XCTAssertEqual(rect.maxY, bounds.maxY, accuracy: 0.5)

        XCTAssertTrue(rect.contains(CGPoint(x: bounds.midX, y: bounds.maxY - closedSize.height / 2)))

        XCTAssertFalse(rect.contains(CGPoint(x: 1, y: bounds.maxY - 1)))
        XCTAssertFalse(rect.contains(CGPoint(x: bounds.maxX - 1, y: bounds.maxY - 1)))
        XCTAssertFalse(rect.contains(CGPoint(x: bounds.midX, y: 1)))
    }

    func testCollapsedRectIncludesHoverMargin() {
        let rect = IslandHitTest.interactiveRect(mode: .collapsed, closedSize: closedSize, bounds: bounds)
        XCTAssertEqual(rect.width, closedSize.width + IslandMetrics.hitTestMargin * 2, accuracy: 0.5)
        XCTAssertEqual(rect.height, closedSize.height + IslandMetrics.hitTestMargin, accuracy: 0.5)
    }

    func testCompactRectCoversWings() {
        let rect = IslandHitTest.interactiveRect(mode: .compact, closedSize: closedSize, bounds: bounds)
        let compactWidth = closedSize.width + IslandMetrics.compactExtraWidth
        XCTAssertEqual(rect.width, compactWidth + IslandMetrics.hitTestMargin * 2, accuracy: 0.5)

        XCTAssertTrue(rect.contains(CGPoint(
            x: bounds.midX - compactWidth / 2 + 10,
            y: bounds.maxY - closedSize.height / 2
        )))
    }

    func testExpandedRectCoversIslandAndIsClampedToPanel() {
        let rect = IslandHitTest.interactiveRect(mode: .expanded, closedSize: closedSize, bounds: bounds)

        XCTAssertEqual(rect.width, bounds.width, accuracy: 0.5)
        XCTAssertTrue(rect.contains(CGPoint(
            x: bounds.midX,
            y: bounds.maxY - IslandMetrics.expandedSize.height + 5
        )))

        XCTAssertFalse(rect.contains(CGPoint(x: bounds.midX, y: 2)))
    }
}
