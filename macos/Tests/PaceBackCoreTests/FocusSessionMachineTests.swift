import XCTest
@testable import PaceBackCore

final class FocusSessionMachineTests: XCTestCase {
    func testHigherCheckInPausesActiveSessionWithoutChangingConfiguredTimes() {
        var machine = FocusSessionMachine(configuration: .init(focusMinutes: 12, restMinutes: 4))
        machine.start()

        XCTAssertTrue(machine.applyCheckIn(startingRating: 2, currentRating: 4))
        XCTAssertEqual(machine.phase, .paused)
        XCTAssertEqual(machine.configuration, .init(focusMinutes: 12, restMinutes: 4))
    }

    func testSameOrLowerCheckInDoesNotPauseOrInterpretRating() {
        var machine = FocusSessionMachine(configuration: .init(focusMinutes: 10, restMinutes: 3))
        machine.start()

        XCTAssertFalse(machine.applyCheckIn(startingRating: 5, currentRating: 5))
        XCTAssertEqual(machine.phase, .focusing)
        XCTAssertFalse(machine.applyCheckIn(startingRating: 5, currentRating: 3))
        XCTAssertEqual(machine.phase, .focusing)
    }

    func testCheckInClampsRatingsAndDoesNothingWhenNotRunning() {
        var machine = FocusSessionMachine(configuration: .init())

        XCTAssertFalse(machine.applyCheckIn(startingRating: -20, currentRating: 99))
        XCTAssertEqual(machine.phase, .ready)
    }

    func testConfigurationClampsToHardLimits() {
        let configuration = FocusSessionConfiguration(focusMinutes: 100, restMinutes: 0)

        XCTAssertEqual(configuration.focusMinutes, 60)
        XCTAssertEqual(configuration.restMinutes, 1)
    }

    func testSessionMovesFromFocusToRestToCompleteWithoutChangingPlan() {
        let configuration = FocusSessionConfiguration(focusMinutes: 1, restMinutes: 1)
        var session = FocusSessionMachine(configuration: configuration)

        session.start()
        XCTAssertEqual(session.phase, .focusing)
        for _ in 0..<60 { session.tick() }
        XCTAssertEqual(session.phase, .resting)
        XCTAssertEqual(session.configuration, configuration)
        for _ in 0..<60 { session.tick() }
        XCTAssertEqual(session.phase, .completed)
        XCTAssertEqual(session.configuration, configuration)
    }

    func testPausePreventsElapsedTimeAndResumeReturnsToFocus() {
        var session = FocusSessionMachine(configuration: .init(focusMinutes: 1, restMinutes: 1))
        session.start()
        session.tick()
        session.pause()
        let elapsed = session.elapsedFocusSeconds

        for _ in 0..<10 { session.tick() }
        XCTAssertEqual(session.elapsedFocusSeconds, elapsed)
        XCTAssertEqual(session.phase, .paused)

        session.resume()
        XCTAssertEqual(session.phase, .focusing)
        session.tick()
        XCTAssertEqual(session.elapsedFocusSeconds, elapsed + 1)
    }

    func testStopEarlyIsTerminal() {
        var session = FocusSessionMachine(configuration: .init())
        session.start()
        session.tick()
        session.stopEarly()
        let elapsed = session.elapsedFocusSeconds

        session.tick()
        session.resume()
        session.start()
        XCTAssertEqual(session.phase, .stoppedEarly)
        XCTAssertEqual(session.elapsedFocusSeconds, elapsed)
    }
}
