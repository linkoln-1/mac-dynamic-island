import XCTest
@testable import PersonalIsland

final class MediaTimeFormatterTests: XCTestCase {
    func testUnderOneHour() {
        XCTAssertEqual(MediaTimeFormatter.format(9), "0:09")
        XCTAssertEqual(MediaTimeFormatter.format(65), "1:05")
        XCTAssertEqual(MediaTimeFormatter.format(3599), "59:59")
    }

    func testOneHourAndAbove() {
        XCTAssertEqual(MediaTimeFormatter.format(3600), "1:00:00")
        XCTAssertEqual(MediaTimeFormatter.format(3937), "1:05:37")
        XCTAssertEqual(MediaTimeFormatter.format(7325), "2:02:05")
    }

    func testDegenerateInputs() {
        XCTAssertEqual(MediaTimeFormatter.format(0), "0:00")
        XCTAssertEqual(MediaTimeFormatter.format(-5), "0:00")
        XCTAssertEqual(MediaTimeFormatter.format(.infinity), "0:00")
        XCTAssertEqual(MediaTimeFormatter.format(.nan), "0:00")
    }

    func testFractionalSecondsTruncate() {
        XCTAssertEqual(MediaTimeFormatter.format(65.9), "1:05")
        XCTAssertEqual(MediaTimeFormatter.format(3599.999), "59:59")
    }
}
