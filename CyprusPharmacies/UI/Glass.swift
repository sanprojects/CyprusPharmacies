//
//  Glass.swift
//  CyprusPharmacies
//

import SwiftUI

enum Margin {
    /// The gap between the screen's edge and a floating element: iOS 26 floats sheets 8 pt off the edge
    /// (measured on iPhone SE), so the map's bar and buttons use the same; earlier systems have no such gap.
    static var screen: CGFloat { if #available(iOS 26, *) { 8 } else { 16 } }
    /// The gap between a sheet's edge and its content.
    static let content: CGFloat = 16
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

    /// Glass button style on iOS 26+, bordered before; `prominent` is glass tinted with the accent color (system blue)
    /// with white semibold text, so the main actions stand out on the sheet and on the map.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent).fontWeight(.semibold)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent).fontWeight(.semibold)
            } else {
                buttonStyle(.bordered)
            }
        }
    }
}

/// A round glass button face, as the Share and Close buttons of Apple's sheets: a dark glyph on clear glass on iOS 26+,
/// on a gray circle before. Used as the label of a plain-style button or a `ShareLink`.
struct CircleButtonLabel: View {
    let systemImage: String

    var body: some View {
        let face = Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            // Explicit color: in a button `.primary` would be the accent color.
            .foregroundStyle(Color(.label))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        if #available(iOS 26, *) {
            face.glassEffect(.regular.interactive(), in: Circle())
        } else {
            face.background(Circle().fill(Color(.tertiarySystemFill)))
        }
    }
}

extension Color {
    /// A card on a sheet: lighter than the sheet's glass on iOS 26+, as Maps' route cards; a grouped cell before.
    static var sheetCard: Color {
        if #available(iOS 26, *) {
            return Color(UIColor { $0.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 1, alpha: 0.55) })
        }
        return Color(.secondarySystemGroupedBackground)
    }
}
