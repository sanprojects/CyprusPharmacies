//
//  PharmacyListView.swift
//  CyprusPharmacies
//

import CoreLocation
import SwiftUI

/// The day's pharmacies as a list, nearest first when the user's position is known.
struct PharmacyListView: View {
    let title: String
    let pharmacies: [Pharmacy]
    let isLoading: Bool
    let distance: (Pharmacy) -> CLLocationDistance?
    let onSelect: (Pharmacy) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if pharmacies.isEmpty {
                    if isLoading {
                        ProgressView()
                    } else {
                        ContentUnavailableView("No duty pharmacies for this day", systemImage: "cross.case")
                    }
                } else {
                    List(pharmacies) { pharmacy in
                        Button { onSelect(pharmacy) } label: {
                            PharmacyRow(pharmacy: pharmacy, distance: distance(pharmacy))
                        }
                        // Plain style keeps the text in label colors instead of the accent color.
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows the pharmacy on the map")
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct PharmacyRow: View {
    let pharmacy: Pharmacy
    let distance: CLLocationDistance?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pharmacy.name.isEmpty ? "Pharmacy" : pharmacy.name)
                    .font(.headline)
                if !pharmacy.address.isEmpty {
                    Text(pharmacy.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let distance {
                Text(Measurement(value: distance, unit: UnitLength.meters)
                    .formatted(.measurement(width: .abbreviated, usage: .road)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
