import XCTest
@testable import PersonalIsland

final class SystemTimerParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func entry(
        state: Int, duration: Double, fireDate: Date? = nil, interval: Double? = nil
    ) -> [String: Any] {
        var timer: [String: Any] = ["MTTimerState": state, "MTTimerDuration": duration]
        if let fireDate {
            timer["MTTimerFireTimerClass"] = "MTTimerDate"
            timer["MTTimerFireTime"] = ["$MTTimerDate": ["MTTimerTimeDate": fireDate]]
        }
        if let interval {
            timer["MTTimerFireTimerClass"] = "MTTimerTimeInterval"
            timer["MTTimerFireTime"] = ["$MTTimerTimeInterval": ["MTTimerTimeInterval": interval]]
        }
        return ["$MTTimer": timer]
    }

    func testRunningTimerCountsDownToItsFireDate() {
        let snapshot = SystemTimerParser.snapshot(from: [
            entry(state: 3, duration: 600, fireDate: now.addingTimeInterval(120)),
        ])
        XCTAssertEqual(snapshot?.mode, .running(fireDate: now.addingTimeInterval(120)))
        XCTAssertEqual(snapshot?.remaining(at: now), 120)
        XCTAssertEqual(snapshot?.progress(at: now) ?? 0, 0.2, accuracy: 0.0001)
        XCTAssertEqual(snapshot?.remaining(at: now.addingTimeInterval(600)), 0, "never goes negative")
        XCTAssertEqual(snapshot?.isPaused, false)
    }

    func testPausedTimerKeepsItsRemainingInterval() {
        let snapshot = SystemTimerParser.snapshot(from: [
            entry(state: 2, duration: 600, interval: 589.75),
        ])
        XCTAssertEqual(snapshot?.isPaused, true)
        XCTAssertEqual(snapshot?.remaining(at: now) ?? 0, 589.75, accuracy: 0.001)
        XCTAssertEqual(
            snapshot?.remaining(at: now.addingTimeInterval(300)) ?? 0, 589.75, accuracy: 0.001,
            "a paused timer does not tick"
        )
        XCTAssertEqual(snapshot?.isEnding(at: now, threshold: 10_000), false)
    }

    func testDismissedAndUnknownStatesAreIgnored() {
        XCTAssertNil(SystemTimerParser.snapshot(from: [entry(state: 1, duration: 90, interval: 90)]))
        XCTAssertNil(SystemTimerParser.snapshot(from: []))
        XCTAssertNil(SystemTimerParser.snapshot(from: [["$MTTimer": ["MTTimerDuration": 60.0]]]))
        XCTAssertNil(
            SystemTimerParser.snapshot(from: [entry(state: 3, duration: 60)]),
            "a running timer without a fire date is not usable"
        )
    }

    func testRunningWinsOverPausedAndSoonestWins() {
        let snapshot = SystemTimerParser.snapshot(from: [
            entry(state: 2, duration: 600, interval: 30),
            entry(state: 3, duration: 900, fireDate: now.addingTimeInterval(500)),
            entry(state: 3, duration: 600, fireDate: now.addingTimeInterval(60)),
            entry(state: 1, duration: 90, interval: 90),
        ])
        XCTAssertEqual(snapshot?.remaining(at: now), 60)
    }

    func testEndingSoonOnlyWhileRunning() {
        let running = SystemTimerParser.snapshot(from: [
            entry(state: 3, duration: 600, fireDate: now.addingTimeInterval(8)),
        ])
        XCTAssertEqual(running?.isEnding(at: now), true)

        let paused = SystemTimerParser.snapshot(from: [entry(state: 2, duration: 600, interval: 5)])
        XCTAssertEqual(paused?.isEnding(at: now), false)
    }

    func testCompactPlanMakesRoomForATimerAlone() {
        var plan = CompactSurfacePlan.plan(
            hasMedia: false, hasAgentSummary: false, highPriorityCount: 0, hasTimer: true
        )
        XCTAssertFalse(plan.isEmpty, "a running timer alone must open the compact island")
        XCTAssertTrue(plan.showsTimer)

        plan = CompactSurfacePlan.plan(
            hasMedia: true, hasAgentSummary: false, highPriorityCount: 0, hasTimer: true
        )
        XCTAssertTrue(plan.showsMicroCluster, "with media the timer lives in the micro zone")

        plan = CompactSurfacePlan.plan(
            hasMedia: false, hasAgentSummary: false, highPriorityCount: 0, hasTimer: false
        )
        XCTAssertTrue(plan.isEmpty)
    }
}
