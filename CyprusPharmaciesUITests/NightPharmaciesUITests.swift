//
//  NightPharmaciesUITests.swift
//  CyprusPharmaciesUITests
//

import XCTest

/// The main flows on a fixed feed, so the tests do not depend on the network or on the day.
@MainActor
final class NightPharmaciesUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    func testListOpensDetailsWithCallAndDirections() {
        launch(feed: Self.feed)

        app.buttons["List of pharmacies"].tap()
        // The card reads the name, then distance and hours, then the address; the map pin behind the sheet has the name alone.
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@",
                                                   "Alpha Pharmacy, ", "1 Makariou Ave., Nicosia"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.tap()

        XCTAssertTrue(app.staticTexts["Alpha Pharmacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Call"].isEnabled)
        app.buttons["Directions"].tap()
        XCTAssertTrue(app.buttons["Apple Maps"].waitForExistence(timeout: 5))
    }

    func testCalendarPicksTomorrow() {
        launch(feed: Self.feed)

        let dayMenu = app.buttons["dayMenu"]
        XCTAssertTrue(dayMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(dayMenu.label.contains("Today"))
        dayMenu.tap()
        // The duty day turns at 08:00 Cyprus time, so tomorrow's date is counted from the duty day.
        var nicosia = Calendar(identifier: .gregorian)
        nicosia.timeZone = TimeZone(identifier: "Asia/Nicosia") ?? .current
        let duty = Date().addingTimeInterval(-8 * 60 * 60)
        let tomorrow = nicosia.component(.day, from: duty.addingTimeInterval(24 * 60 * 60))
        let cell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(tomorrow), ")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), app.debugDescription)
        cell.tap()

        let shown = NSPredicate(format: "label CONTAINS %@", "Tomorrow")
        expectation(for: shown, evaluatedWith: dayMenu)
        waitForExpectations(timeout: 5)
    }

    func testOfflineWithoutCacheShowsNoInternet() {
        launch(feed: Self.feed, arguments: ["-simulateOffline", "YES"])

        XCTAssertTrue(app.staticTexts["No internet connection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Try again"].exists)
    }

    private func launch(feed: String, arguments: [String] = []) {
        app.launchEnvironment["PHARMACIES_FIXTURE"] = feed
        app.launchArguments = ["-resetCache", "YES"] + arguments
        app.launch()
    }

    /// Two pharmacies on duty today in Cyprus time: one number each, so Call dials at once.
    private static var feed: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Nicosia")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let tomorrow = formatter.string(from: Date().addingTimeInterval(24 * 60 * 60))
        return """
        [
          {"date": "\(today)", "name": "Alpha Pharmacy", "originalname": "Φαρμακείο Άλφα",
           "address": "1 Makariou Ave., Nicosia", "originalAddress": "", "pharmacyPhone": "+35722000001", "homePhone": "",
           "lat": 35.17, "lng": 33.36, "gesyId": "", "description": "Works until 8:00 AM \(tomorrow)\\nCall before you go!"},
          {"date": "\(today)", "name": "Beta Pharmacy", "originalname": "",
           "address": "2 Anexartisias St., Limassol", "originalAddress": "", "pharmacyPhone": "+35725000002", "homePhone": "",
           "lat": 34.68, "lng": 33.04, "gesyId": "", "description": ""}
        ]
        """
    }
}
