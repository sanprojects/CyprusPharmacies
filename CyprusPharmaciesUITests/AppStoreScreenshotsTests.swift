//
//  AppStoreScreenshotsTests.swift
//  CyprusPharmaciesUITests
//

import XCTest

/// App Store screenshots on a fixed feed; runs only when asked, and writes the PNGs to the given folder:
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
        app.launchEnvironment["PHARMACIES_FIXTURE"] = Self.feed
        app.launchArguments = ["-resetCache", "YES"]
        app.launch()

        XCTAssertTrue(app.buttons["dayMenu"].waitForExistence(timeout: 10))
        sleep(4)
        capture("1-map", to: path)

        app.buttons["List of pharmacies"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alpha Pharmacy, ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        sleep(2)
        capture("2-list", to: path)

        row.tap()
        XCTAssertTrue(app.buttons["Call"].waitForExistence(timeout: 8))
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

    /// Seven pharmacies on duty today in Cyprus time, across the island.
    private static var feed: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Nicosia")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let tomorrow = formatter.string(from: Date().addingTimeInterval(24 * 60 * 60))
        let rows = [
            ("Alpha Pharmacy", "Φαρμακείο Άλφα", "1 Makariou III Ave., Nicosia", "35722000001", 35.1700, 33.3600),
            ("Agios Dometios Pharmacy", "", "24 Griva Digeni St., Nicosia", "35722000003", 35.1580, 33.3290),
            ("Engomi Pharmacy", "", "7 Kennedy Ave., Nicosia", "35722000008", 35.1460, 33.3410),
            ("Beta Pharmacy", "", "2 Anexartisias St., Limassol", "35725000002", 34.6850, 33.0400),
            ("Molos Pharmacy", "", "12 Amathountos Ave., Limassol", "35725000004", 34.6760, 33.0620),
            ("Larnaca Seafront Pharmacy", "", "5 Athinon Ave., Larnaca", "35724000005", 34.9170, 33.6350),
            ("Paphos Harbour Pharmacy", "", "8 Poseidonos Ave., Paphos", "35726000006", 34.7580, 32.4100),
            ("Ayia Napa Pharmacy", "", "3 Kryou Nerou Ave., Ayia Napa", "35723000007", 34.9880, 34.0120),
        ]
        let items = rows.map { name, original, address, phone, lat, lng in
            """
            {"date": "\(today)", "name": "\(name)", "originalname": "\(original)", "address": "\(address)",
             "originalAddress": "", "pharmacyPhone": "+\(phone)", "homePhone": "", "lat": \(lat), "lng": \(lng),
             "gesyId": "", "description": "Works until 8:00 AM \(tomorrow)\\nCall before you go!"}
            """
        }
        return "[" + items.joined(separator: ",") + "]"
    }
}
