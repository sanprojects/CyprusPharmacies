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
        VStack(alignment: .leading, spacing: 16) {
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

            if !pharmacy.address.isEmpty {
                AddressRow(title: "Address", text: pharmacy.address)
            }
            if !pharmacy.originalAddress.isEmpty {
                AddressRow(title: "Address in Greek", text: pharmacy.originalAddress)
            }
            if !pharmacy.description.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Hours", systemImage: "clock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(pharmacy.description)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                Button {
                    isCallDialogShown = true
                } label: {
                    Label("Call", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
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
                    Label("Get directions", systemImage: "car.fill")
                        .frame(maxWidth: .infinity)
                }
                .confirmationDialog("Get directions", isPresented: $isDirectionsDialogShown, titleVisibility: .visible) {
                    ForEach(Navigator.allCases) { navigator in
                        Button(navigator.rawValue) { navigator.open(to: pharmacy.coordinate) }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
    }
}

/// Address that offers "Copy address" when tapped.
private struct AddressRow: View {
    let title: String
    let text: String

    var body: some View {
        Menu {
            Button("Copy address", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = text
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityHint("Shows Copy address")
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
