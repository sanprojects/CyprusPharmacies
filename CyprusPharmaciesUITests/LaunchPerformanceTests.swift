//
//  LaunchPerformanceTests.swift
//  CyprusPharmaciesUITests
//

import XCTest

/// Cold launch time. Slow (five launches), so it runs only when asked:
/// `TEST_RUNNER_RUN_LAUNCH_METRIC=1 xcodebuild test -configuration Release -only-testing:NightPharmaciesUITests/LaunchPerformanceTests …`
@MainActor
final class LaunchPerformanceTests: XCTestCase {
    func testLaunch() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LAUNCH_METRIC"] == "1", "Set TEST_RUNNER_RUN_LAUNCH_METRIC=1")
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
