# App Store Connect — Night Pharmacy

Bundle ID `com.elenakim.NightPharmacies` · Team `9R966FQAD6` · Version 2.0 (build 1) · iOS 17.0+ · iPhone + iPad

## Already live: Cyprus Night Pharmacies, v1.3 (2023-06-15), same bundle ID
Source: `curl -s "https://itunes.apple.com/lookup?id=1637452137&country=cy"` and the store page <https://apps.apple.com/cy/app/cyprus-night-pharmacies/id1637452137>. This is an update of that app: keep its name, category and links.

- **Privacy Policy URL:** https://sites.google.com/view/nightpharmacies (the store page's "Privacy Policy" link; it covers Log Data collected through third-party products, i.e. crash reports)
- **Support URL:** not shown on the public store page; App Store Connect keeps the field from v1.3 when you add a new version. If it is empty, use the privacy page above.
- **Review contact email:** lilena88@gmail.com (the only contact on the privacy page); name and phone are still needed for App Review.
- **Copyright:** store shows `© 2022, Elena Kim`; for this version `2026 Elena Kim`.
- **Review note:** "No sign-in. Duty-pharmacy data comes from https://sanstv.ru/pharmacies/data/today.php; Location is optional."
- Version history for the store: 1.3 → this build is 2.0 (build 1).

## Text (en-US)
- **Name:** Cyprus Night Pharmacies (as live; the home-screen name is Night Pharmacy)
- **Subtitle (30):** Duty pharmacies in Cyprus
- **Promotional text (170):** Find the pharmacy that is open tonight, anywhere in Cyprus. See every duty pharmacy on the map, call it or get directions in one tap.
- **Keywords (100):** pharmacy,chemist,duty,night,24h,open now,emergency,medicine,Cyprus,Nicosia,Limassol,Larnaca,Paphos
- **Description:**
  Night Pharmacy shows which pharmacies in Cyprus are on duty today, tomorrow and on any day the official schedule covers.

  - Map of all duty pharmacies, grouped into clusters when zoomed out
  - List sorted by distance, with opening hours and "on call" hours
  - One tap to call the pharmacy or open directions in Apple Maps, Google Maps or Waze
  - A calendar of the days with pharmacies, swipe the date bar to change the day
  - Works with your location when you allow it; without it the whole island is shown
  - Liquid Glass design on iOS 26, native look on iOS 17 and later; iPhone and iPad

  Data comes from the Cyprus Ministry of Health duty schedule. The duty day changes at 08:00 Cyprus time. Always call before you go.

- **What's New (2.0):**
  Completely rebuilt in SwiftUI with the new Liquid Glass look on iOS 26, and now on iPad too.
  - Pharmacy list sorted by distance, with opening hours
  - Calendar of duty days; swipe the date bar to change the day, double-tap it to return to today
  - Directions in Apple Maps, Google Maps or Waze
  - The map opens fitted to all of the day's pharmacies
  Requires iOS 17 or later.

## Classification
- **Primary category:** Medical (as live)
- **Age rating:** 4+ (as live)
- **Price:** Free

## App Privacy (nutrition label)
- Tracking: **No** (`PrivacyInfo.xcprivacy`: NSPrivacyTracking false)
- Data collected, not linked to the user, not used for tracking, purpose App Functionality: **Crash Data**, **Other Diagnostic Data** (Sentry)
- Location: used on the device to sort the list and draw the user's position; never sent anywhere, so not "collected"
- Export compliance: `ITSAppUsesNonExemptEncryption = NO` (set in `project.yml`)

## Screenshots (`AppStore/screenshots`)
| Folder | Pixels | App Store slot |
|---|---|---|
| `iphone-6.9-pro-max` | 1320x2868 | iPhone 6.9" (required) |
| `ipad-13` | 2064x2752 | iPad 13" (required, the app is universal) |
| `iphone-17-1206x2622` | 1206x2622 | iPhone 17 native; **not an accepted App Store size** |

Regenerate: boot the simulator, `xcrun simctl status_bar <udid> override --time 9:41 …`, then
`TEST_RUNNER_SCREENSHOT_DIR=<dir> xcodebuild test -project NightPharmacies.xcodeproj -scheme NightPharmacies -destination "id=<udid>" -only-testing:NightPharmaciesUITests/AppStoreScreenshotsTests`

## Upload
`xcodebuild archive … && xcodebuild -exportArchive -exportOptionsPlist ExportOptions.plist` (method app-store-connect, automatic signing) succeeded locally; upload with Xcode Organizer or `xcrun altool`/Transporter. Raise `CURRENT_PROJECT_VERSION` for every re-upload.
