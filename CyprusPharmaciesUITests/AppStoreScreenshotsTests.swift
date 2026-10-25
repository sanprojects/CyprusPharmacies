//
//  AppStoreScreenshotsTests.swift
//  CyprusPharmaciesUITests
//

import XCTest

/// App Store screenshots on the real feed (needs the network); runs only when asked, and writes the PNGs to the given folder:
/// `TEST_RUNNER_SCREENSHOT_DIR=/path xcodebuild test -only-testing:NightPharmaciesUITests/AppStoreScreenshotsTests …`
/// Set the status bar first: `xcrun simctl status_bar <udid> override --time 9:41 …`
@MainActor
final class AppStoreScreenshotsTests: XCTestCase {
    private let app = XCUIApplication()

    func testCaptureScreenshots() throws {
        let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"]
        try XCTSkipIf(directory?.isEmpty ?? true, "Set TEST_RUNNER_SCREENSHOT_DIR")
        let path = directory ?? ""
        continueAfterFailure = false
        app.launchArguments = ["-resetCache", "YES"]
        app.launch()

        XCTAssertTrue(app.buttons["dayMenu"].waitForExistence(timeout: 10))
        sleep(4)
        capture("1-map", to: path)

        app.buttons["List of pharmacies"].tap()
        // A card reads "name, hours, address"; map pins have the name alone, clusters end in "zoom in",
        // and the date bar and Directions have identifiers.
        let row = app.buttons.matching(NSPredicate(
            format: "label CONTAINS ', ' AND NOT label ENDSWITH 'zoom in' AND identifier == ''")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        sleep(2)
        capture("2-list", to: path)

        row.tap()
        XCTAssertTrue(app.buttons["Call"].waitForExistence(timeout: 8), app.debugDescription)
        sleep(4)
        capture("3-details", to: path)

        app.buttons["Close"].firstMatch.tap()
        sleep(1)
        app.buttons["dayMenu"].tap()
        sleep(2)
        capture("4-calendar", to: path)
    }

    private func capture(_ name: String, to directory: String) {
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertNoThrow(try XCUIScreen.main.screenshot().pngRepresentation.write(to: url))
    }
}
