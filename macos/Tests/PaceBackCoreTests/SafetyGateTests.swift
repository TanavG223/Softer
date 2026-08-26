import XCTest
@testable import PaceBackCore

final class SafetyGateTests: XCTestCase {
    func testNoSelectedSignsIsClear() {
        XCTAssertEqual(SafetyGate.evaluate(selected: [], ageBand: .adult18To64), .clear)
    }

    func testAnyCommonDangerSignImmediatelyReturnsStaticEmergencyInstructions() {
        let result = SafetyGate.evaluate(selected: [.seizure], ageBand: .teen13To17)

        guard case .emergency(let signs, let instructions) = result else {
            return XCTFail("Expected deterministic emergency result")
        }
        XCTAssertEqual(signs, [.seizure])
        XCTAssertEqual(instructions, SafetyGate.emergencyInstructions)
        XCTAssertTrue(instructions.contains("911"))
        XCTAssertTrue(instructions.contains("Do not wait for an AI response"))
    }

    func testYoungChildIncludesBehavioralDangerSigns() {
        let signs = SafetyGate.signs(for: .youngChild0To5)

        XCTAssertTrue(signs.contains(.inconsolableCrying))
        XCTAssertTrue(signs.contains(.refusesToNurseOrEat))
        XCTAssertTrue(SafetyGate.evaluate(
            selected: [.refusesToNurseOrEat],
            ageBand: .youngChild0To5
        ).isEmergency)
    }

    func testYoungChildOnlySignCannotLeakIntoAdultEvaluation() {
        let result = SafetyGate.evaluate(selected: [.inconsolableCrying], ageBand: .adult18To64)

        XCTAssertEqual(result, .clear)
        XCTAssertFalse(SafetyGate.signs(for: .adult18To64).contains(.inconsolableCrying))
    }

    func testMultipleSignsAreStableAndNonDuplicated() {
        let result = SafetyGate.evaluate(
            selected: [.slurredSpeech, .seizure, .slurredSpeech],
            ageBand: .olderAdult65Plus
        )

        guard case .emergency(let signs, _) = result else { return XCTFail("Expected emergency") }
        XCTAssertEqual(signs, [.seizure, .slurredSpeech])
    }
}
