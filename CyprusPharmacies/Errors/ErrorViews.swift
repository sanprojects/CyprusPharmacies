//
//  ErrorViews.swift
//  CyprusPharmacies
//

import SwiftUI

/// Shown instead of the map when the device is offline and the day has no cache.
struct NoInternetView: View {
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No internet connection", systemImage: "wifi.slash")
        } description: {
            Text("Connect to the internet to load the duty pharmacies for this day. Days you have already opened are available offline.")
        } actions: {
            Button("Try again", action: onRetry)
                .glassButtonStyle(prominent: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

/// Server, parsing, timeout and other load errors.
struct LoadFailureView: View {
    let onOK: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Something went wrong. Try later")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button(action: onOK) {
                    Text("OK").frame(maxWidth: .infinity)
                }
                .glassButtonStyle(prominent: true)
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .glassBackground(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(32)
        }
        .accessibilityAddTraits(.isModal)
    }
}
