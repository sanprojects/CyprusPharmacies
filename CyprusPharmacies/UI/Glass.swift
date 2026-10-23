//
//  Glass.swift
//  CyprusPharmacies
//

import SwiftUI

extension Color {
    /// The app's green: white text on it has 4.5:1, more with Increase Contrast.
    static let pharmacyGreen = Color("greenPharm")
}

extension View {
    /// Liquid Glass behind the view on iOS 26+, a material with a shadow before.
    @ViewBuilder
    func glassBackground<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
    }

    /// Glass button style on iOS 26+, bordered before; `prominent` is green glass with white semibold text,
    /// so the main actions stand out on a light sheet and on the map.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent).tint(.pharmacyGreen).fontWeight(.semibold)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent).tint(.pharmacyGreen).fontWeight(.semibold)
            } else {
                buttonStyle(.bordered)
            }
        }
    }
}
