//
//  PharmacyDetailsView.swift
//  CyprusPharmacies
//

import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Content of the Details bottom sheet. Reports its natural height so the sheet can fit it.
struct PharmacyDetailsView: View {
    let pharmacy: Pharmacy
    /// Straight-line distance from the user; nil when their position is unknown.
    let distance: CLLocationDistance?
    let onHeightChange: (CGFloat) -> Void
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isCallDialogShown = false
    @State private var isDirectionsDialogShown = false
    @State private var contentHeight: CGFloat = 0
    @State private var buttonsHeight: CGFloat = 0
    @State private var travelTime: TimeInterval?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    })
            }
            .scrollBounceBehavior(.basedOnSize)

            // Outside the scroll view, so Call and Directions stay on screen whatever the text size.
            buttons
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ButtonsHeightKey.self, value: proxy.size.height)
                })
        }
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0; reportHeight() }
        .onPreferenceChange(ButtonsHeightKey.self) { buttonsHeight = $0; reportHeight() }
        .task(id: pharmacy.id) { await loadTravelTime() }
    }

    private func reportHeight() {
        if contentHeight > 0 && buttonsHeight > 0 { onHeightChange(contentHeight + buttonsHeight) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            VStack(alignment: .leading, spacing: 0) {
                let hasAddress = !pharmacy.address.isEmpty || !pharmacy.originalAddress.isEmpty
                if hasAddress {
                    AddressRow(address: pharmacy.address, greekAddress: pharmacy.originalAddress)
                }
                if !pharmacy.description.isEmpty {
                    if hasAddress { RowDivider() }
                    HoursRow(pharmacy: pharmacy)
                }
                if let distance {
                    if hasAddress || !pharmacy.description.isEmpty { RowDivider() }
                    DetailRow(systemImage: "car") {
                        Text(Self.travelText(distance: distance, travelTime: travelTime))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var header: some View {
        Group {
            // At accessibility sizes the name gets the full width, under the buttons.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Spacer()
                        headerButtons
                    }
                    title
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    title
                    headerButtons
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pharmacy.name.isEmpty ? "Pharmacy" : pharmacy.name)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if let greekName = pharmacy.greekName {
                Text(greekName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var headerButtons: some View {
        if let url = pharmacy.appleMapsURL {
            ShareLink(item: url, subject: Text(pharmacy.name), message: Text(shareMessage)) {
                headerIcon("square.and.arrow.up.circle.fill")
            }
            .accessibilityLabel("Share")
        }
        Button(action: onClose) {
            headerIcon("xmark.circle.fill")
        }
        .accessibilityLabel("Close")
    }

    private func headerIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title2)
            // Gray glyph on a filled circle, as Apple's sheets have; explicit colors, since in a button
            // `.secondary` is a shade of the accent color.
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color(.secondaryLabel), Color(.systemFill))
            // Big enough to hit, without crowding the name at the largest sizes.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var shareMessage: String {
        [pharmacy.name, pharmacy.address].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private var buttons: some View {
        // Side by side, or one under the other at accessibility text sizes.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button(action: call) {
                Label("Call", systemImage: "phone.fill")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .disabled(pharmacy.phoneOptions.isEmpty)
            .confirmationDialog("Call", isPresented: $isCallDialogShown, titleVisibility: .visible) {
                ForEach(pharmacy.phoneOptions, id: \.self) { option in
                    Button("\(option.kind.title): \(option.number)") {
                        if let url = option.dialURL { openURL(url) }
                    }
                }
            }

            Button {
                isDirectionsDialogShown = true
            } label: {
                Label("Directions", systemImage: "car.fill")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .confirmationDialog("Directions", isPresented: $isDirectionsDialogShown, titleVisibility: .visible) {
                ForEach(Navigator.allCases) { navigator in
                    Button(navigator.rawValue) { navigator.open(to: pharmacy.coordinate) }
                }
            }
        }
        .lineLimit(1)
        // Both buttons take the height of the taller one.
        .fixedSize(horizontal: false, vertical: true)
        .glassButtonStyle(prominent: true)
        .controlSize(.large)
    }

    /// One number is dialled at once; with two the user picks.
    private func call() {
        let options = pharmacy.phoneOptions
        if options.count == 1, let url = options[0].dialURL {
            openURL(url)
        } else {
            isCallDialogShown = true
        }
    }

    private func loadTravelTime() async {
        guard distance != nil else { return }
        let request = MKDirections.Request()
        request.source = .forCurrentLocation()
        request.destination = Self.mapItem(at: pharmacy.coordinate)
        request.transportType = .automobile
        // On failure the row keeps the straight-line distance. MapKit has no routing in Cyprus yet
        // (FAILED_NO_RESULT, October 2026), so there this is the usual case.
        travelTime = try? await MKDirections(request: request).calculateETA().expectedTravelTime
    }

    private static func mapItem(at coordinate: CLLocationCoordinate2D) -> MKMapItem {
        if #available(iOS 26, *) {
            return MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        }
        return MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
    }

    /// "2.4 km away" or, once MapKit answers, "2.4 km · 7 min by car".
    static func travelText(distance: CLLocationDistance, travelTime: TimeInterval?) -> String {
        let length = Measurement(value: distance, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
        guard let travelTime else { return "\(length) away" }
        let minutes = max(1, Int((travelTime / 60).rounded()))
        let time = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return "\(length) · \(time) by car"
    }
}

/// Width of the icon column; text and separators start after it.
private let iconColumnWidth: CGFloat = 28
private let iconSpacing: CGFloat = 14

/// A row with an accent-colored icon on the left and primary text, as in Settings or Maps place cards.
private struct DetailRow<Content: View>: View {
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        // The icon sits on the first line, however many lines the text wraps to.
        HStack(alignment: .firstTextBaseline, spacing: iconSpacing) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: iconColumnWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                content
            }
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Separator that starts under the text, not under the icon.
private struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, iconColumnWidth + iconSpacing)
    }
}

/// "Open now, until 11:00 PM" and the on-call hours; the raw description when it is in an unknown format.
private struct HoursRow: View {
    let pharmacy: Pharmacy

    var body: some View {
        let hours = DutyHours(description: pharmacy.description, dutyDay: pharmacy.date)
        TimelineView(.everyMinute) { context in
            DetailRow(systemImage: "clock") {
                if let hours {
                    Text(hours.headline(at: context.date))
                    ForEach(hours.details(at: context.date), id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(pharmacy.description)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Hours"))
            .accessibilityValue(Text(hours.map { ([$0.headline(at: context.date)] + $0.details(at: context.date)).joined(separator: ", ") }
                                     ?? pharmacy.description))
        }
    }
}

/// English and Greek address; tapping offers "Copy address".
private struct AddressRow: View {
    let address: String
    let greekAddress: String

    var body: some View {
        Menu {
            if !address.isEmpty {
                Button("Copy address", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = address
                }
            }
            if !greekAddress.isEmpty {
                Button("Copy address in Greek", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = greekAddress
                }
            }
        } label: {
            DetailRow(systemImage: "mappin.and.ellipse") {
                if !address.isEmpty {
                    Text(address)
                }
                if !greekAddress.isEmpty {
                    Text(greekAddress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // Plain style keeps the text in label colors instead of the accent color.
        .buttonStyle(.plain)
        .accessibilityLabel("Address, \([address, greekAddress].filter { !$0.isEmpty }.joined(separator: ", "))")
        .accessibilityHint("Shows Copy address")
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ButtonsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
