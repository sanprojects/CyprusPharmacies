//
//  Glass.swift
//  CyprusPharmacies
//

import SwiftUI

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

    /// Glass button style on iOS 26+, bordered before; `prominent` fills it with the accent color.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}
