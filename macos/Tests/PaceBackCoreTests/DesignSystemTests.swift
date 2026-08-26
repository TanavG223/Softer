import SwiftUI
import XCTest
@testable import PaceBackCore

final class DesignSystemTests: XCTestCase {
    func testTextScaleMapsToBoundedDynamicTypeSizes() {
        XCTAssertEqual(PaceBackDesign.dynamicTypeSize(for: 0.9), .small)
        XCTAssertEqual(PaceBackDesign.dynamicTypeSize(for: 1.0), .medium)
        XCTAssertEqual(PaceBackDesign.dynamicTypeSize(for: 1.1), .large)
        XCTAssertEqual(PaceBackDesign.dynamicTypeSize(for: 1.3), .xLarge)
        XCTAssertEqual(PaceBackDesign.dynamicTypeSize(for: 1.5), .xxLarge)
        XCTAssertEqual(PaceBackDesign.dynamicTypeSize(for: 99), .xxLarge)
    }

    func testLargeTextScaleAlsoEnlargesNativeControls() {
        XCTAssertEqual(PaceBackDesign.controlSize(for: 1.0), .regular)
        XCTAssertEqual(PaceBackDesign.controlSize(for: 1.24), .regular)
        XCTAssertEqual(PaceBackDesign.controlSize(for: 1.25), .extraLarge)
        XCTAssertEqual(PaceBackDesign.controlSize(for: 1.5), .extraLarge)
    }
}
