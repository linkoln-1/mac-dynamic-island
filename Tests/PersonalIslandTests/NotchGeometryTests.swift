import XCTest
@testable import PersonalIsland

final class NotchGeometryTests: XCTestCase {
    func testClosedSizeMatchesVerifiedMachineValues() {

        let size = NotchGeometryProvider.closedSize(
            screenWidth: 2056,
            safeAreaTop: 38,
            auxiliaryLeftWidth: 918,
            auxiliaryRightWidth: 918,
            menuBarHeight: 38
        )

        XCTAssertEqual(size.width, 220 + NotchGeometryProvider.notchEdgeOverlap)
        XCTAssertEqual(size.height, 38)
    }

    func testNoNotchFallbackUsesMenuBarHeight() {
        let size = NotchGeometryProvider.closedSize(
            screenWidth: 2560,
            safeAreaTop: 0,
            auxiliaryLeftWidth: nil,
            auxiliaryRightWidth: nil,
            menuBarHeight: 24
        )

        XCTAssertEqual(size.width, NotchGeometryProvider.fakeIslandWidth)
        XCTAssertEqual(size.height, 24)
    }

    func testNoNotchZeroMenuBarUsesConstantGuard() {

        let size = NotchGeometryProvider.closedSize(
            screenWidth: 2560,
            safeAreaTop: 0,
            auxiliaryLeftWidth: nil,
            auxiliaryRightWidth: nil,
            menuBarHeight: 0
        )

        XCTAssertEqual(size.height, NotchGeometryProvider.fallbackBarHeight)
        XCTAssertEqual(size.height, 32)
    }

    func testNotchWithMissingAuxiliaryAreasFallsBackToFakeIsland() {

        let size = NotchGeometryProvider.closedSize(
            screenWidth: 2056,
            safeAreaTop: 38,
            auxiliaryLeftWidth: nil,
            auxiliaryRightWidth: nil,
            menuBarHeight: 38
        )

        XCTAssertEqual(size.width, NotchGeometryProvider.fakeIslandWidth)
        XCTAssertEqual(size.height, 38)
    }

    func testNotchRectIsCenteredAndGluedToTop() {
        let screenFrame = CGRect(x: 0, y: 0, width: 2056, height: 1329)
        let closed = CGSize(width: 224, height: 38)

        let rect = NotchGeometryProvider.notchRect(screenFrame: screenFrame, closedSize: closed)

        XCTAssertEqual(rect.midX, screenFrame.midX)
        XCTAssertEqual(rect.maxY, screenFrame.maxY)
        XCTAssertEqual(rect.width, 224)
        XCTAssertEqual(rect.height, 38)
    }

    func testNotchRectRespectsNonZeroScreenOrigin() {

        let screenFrame = CGRect(x: 2056, y: -200, width: 1920, height: 1080)
        let closed = CGSize(width: 190, height: 32)

        let rect = NotchGeometryProvider.notchRect(screenFrame: screenFrame, closedSize: closed)

        XCTAssertEqual(rect.midX, screenFrame.midX)
        XCTAssertEqual(rect.maxY, screenFrame.maxY)
    }
}
