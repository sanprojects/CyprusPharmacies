//
//  PharmacyListView.swift
//  CyprusPharmacies
//

import CoreLocation
import SwiftUI

/// The day's pharmacies as cards, as Maps lists its routes, nearest first when the user's position is known.
struct PharmacyListView: View {
    let title: String
    let pharmacies: [Pharmacy]
    let isLoading: Bool
    let distance: (Pharmacy) -> CLLocationDistance?
    /// Where the user is, when known: Directions then points to the pharmacy.
    let userCoordinate: CLLocationCoordinate2D?
    let onSelect: (Pharmacy) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            if pharmacies.isEmpty {
                Group {
                    if isLoading {
                        ProgressView()
                    } else {
                        ContentUnavailableView("No duty pharmacies for this day", systemImage: "cross.case")
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(pharmacies.enumerated()), id: \.element.id) { index, pharmacy in
                            let distance = distance(pharmacy)
                            PharmacyCard(pharmacy: pharmacy, distance: distance, userCoordinate: userCoordinate,
                                         // The list is sorted by distance once it is known.
                                         isNearest: index == 0 && distance != nil,
                                         onSelect: { onSelect(pharmacy) })
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .background {
            if #unavailable(iOS 26) {
                Color(.systemGroupedBackground).ignoresSafeArea()
            }
        }
        .sheetGlass()
    }

    /// The day in the middle and Close on the right, as in Maps' Directions sheet.
    private var header: some View {
        HStack(spacing: 12) {
            // Keeps the title centered against Close.
            Color.clear.frame(width: 44, height: 44)
            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if !pharmacies.isEmpty {
                    Text("^[\(pharmacies.count) pharmacy](inflect: true)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            Button { dismiss() } label: {
                CircleButtonLabel(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

/// A pharmacy: name, distance and hours, address; Directions on the right, as Maps' GO.
private struct PharmacyCard: View {
    let pharmacy: Pharmacy
    let distance: CLLocationDistance?
    let userCoordinate: CLLocationCoordinate2D?
    let isNearest: Bool
    let onSelect: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isDirectionsDialogShown = false
    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        // At accessibility sizes Directions goes under the text, which gets the full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Button(action: onSelect) {
                info.frame(maxWidth: .infinity, alignment: .leading)
            }
            // Plain style keeps the text in label colors instead of the accent color.
            .buttonStyle(.plain)
            .accessibilityHint("Shows the pharmacy on the map")

            Button {
                isDirectionsDialogShown = true
            } label: {
                VStack(spacing: 2) {
                    if let userCoordinate {
                        BearingIcon(bearing: PharmacyDetailsView.bearing(from: userCoordinate, to: pharmacy.coordinate))
                            .font(.title2)
                    } else {
                        Image(systemName: "car.fill")
                            .font(.title2)
                    }
                    if let distanceText {
                        Text(distanceText)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(width: 64, height: 64)
            }
            .glassButtonStyle(prominent: true)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .accessibilityLabel("Directions")
            .accessibilityValue(distanceText ?? "")
            .confirmationDialog("Directions", isPresented: $isDirectionsDialogShown, titleVisibility: .visible) {
                ForEach(Navigator.allCases) { navigator in
                    Button(navigator.rawValue) { navigator.open(to: pharmacy.coordinate) }
                }
            }
        }
        .padding(16)
        .background(Color.sheetCard, in: shape)
        .overlay {
            if isNearest { shape.strokeBorder(.tint, lineWidth: 2) }
        }
        .contentShape(shape)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(pharmacy.name.isEmpty ? "Pharmacy" : pharmacy.name)
                .font(.title3.bold())
            if let summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if !pharmacy.address.isEmpty {
                Text(pharmacy.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if isNearest {
                Text("Nearest")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "2.4 km", under the arrow on Directions.
    private var distanceText: String? {
        distance.map {
            Measurement(value: $0, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
        }
    }

    /// "Open now, until 11:00 PM"; the distance is on the Directions button.
    private var summary: String? {
        DutyHours(description: pharmacy.description, dutyDay: pharmacy.date)?.headline(at: .now)
    }
}
