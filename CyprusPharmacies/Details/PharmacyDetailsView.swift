//
//  PharmacyDetailsView.swift
//  CyprusPharmacies
//

import SwiftUI
import UIKit

/// Content of the Details bottom sheet. Reports its natural height so the sheet can fit it.
struct PharmacyDetailsView: View {
    let pharmacy: Pharmacy
    let onHeightChange: (CGFloat) -> Void
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var isCallDialogShown = false
    @State private var isDirectionsDialogShown = false

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 12)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                })
        }
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(ContentHeightKey.self) { height in
            if height > 0 { onHeightChange(height) }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(pharmacy.name.isEmpty ? "Pharmacy" : pharmacy.name)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
            }

            VStack(alignment: .leading, spacing: 0) {
                if !pharmacy.address.isEmpty || !pharmacy.originalAddress.isEmpty {
                    AddressRow(address: pharmacy.address, greekAddress: pharmacy.originalAddress)
                }
                if !pharmacy.description.isEmpty {
                    if !pharmacy.address.isEmpty || !pharmacy.originalAddress.isEmpty {
                        RowDivider()
                    }
                    DetailRow(systemImage: "clock") {
                        Text(pharmacy.description)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Hours, \(pharmacy.description)")
                }
            }

            HStack(spacing: 12) {
                Button {
                    isCallDialogShown = true
                } label: {
                    Label("Call", systemImage: "phone.fill")
                        .lineLimit(1)
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
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .confirmationDialog("Directions", isPresented: $isDirectionsDialogShown, titleVisibility: .visible) {
                    ForEach(Navigator.allCases) { navigator in
                        Button(navigator.rawValue) { navigator.open(to: pharmacy.coordinate) }
                    }
                }
            }
            // Both buttons take the height of the taller one.
            .fixedSize(horizontal: false, vertical: true)
            .glassButtonStyle(prominent: true)
            .controlSize(.large)
            .padding(.top, 4)
        }
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
        HStack(alignment: .center, spacing: iconSpacing) {
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
