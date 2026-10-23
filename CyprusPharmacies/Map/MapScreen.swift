//
//  MapScreen.swift
//  CyprusPharmacies
//

import SwiftUI
import UIKit

struct MapScreen: View {
    @Bindable var model: MapViewModel

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var topBarBottom: CGFloat = 0
    @State private var sheetHeight: CGFloat = 0
    @State private var isInfoShown = false
    /// Info was tapped while Details was up: show it once that sheet is gone.
    @State private var showsInfoAfterDetails = false
    @State private var hasStarted = false

    var body: some View {
        GeometryReader { root in
            ZStack(alignment: .top) {
                if model.blocking == .noInternet {
                    NoInternetView { model.retry() }
                        .padding(.top, topBarBottom)
                        .ignoresSafeArea()
                } else {
                    map
                    controls
                }

                topBar
                    .padding(.horizontal, 12)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: TopBarBottomKey.self, value: proxy.frame(in: .global).maxY)
                    })

                if model.blocking == .failure {
                    LoadFailureView { model.dismissFailure() }
                }
            }
            .onPreferenceChange(TopBarBottomKey.self) { topBarBottom = $0 }
            .onChange(of: model.selected?.id) { _, _ in
                // Another pin with a sheet of the same height reports no new height: focus it here.
                if let pharmacy = model.selected, sheetHeight > 0 {
                    model.focus(on: pharmacy, bottomInset: sheetHeight + root.safeAreaInsets.bottom)
                }
            }
            .sheet(isPresented: detailsShown, onDismiss: detailsDismissed) {
                if let pharmacy = model.selected {
                    PharmacyDetailsView(
                        pharmacy: pharmacy,
                        onHeightChange: { height in
                            sheetHeight = height
                            model.focus(on: pharmacy, bottomInset: height + root.safeAreaInsets.bottom)
                        },
                        onClose: { model.select(nil) }
                    )
                    .id(pharmacy.id)
                    .presentationDetents([.height(sheetHeight > 0 ? min(sheetHeight, root.size.height * 0.75) : 320)])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled)
                }
            }
        }
        .sheet(isPresented: $isInfoShown) {
            InfoView()
                .presentationDetents([.medium, .large])
        }
        .alert("Location access is off", isPresented: $model.isLocationDeniedAlertShown) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow location access in Settings to see where you are and the nearest duty pharmacy.")
        }
        .onAppear {
            guard !hasStarted else { return }
            hasStarted = true
            model.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && hasStarted { model.refreshIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            model.refreshIfNeeded()
        }
    }

    private var map: some View {
        PharmacyMapView(
            pharmacies: model.pharmacies,
            selected: model.selected,
            command: model.mapCommand,
            showsUserLocation: model.showsUserLocation,
            topInset: topBarBottom,
            onSelect: { model.select($0) }
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            dayButton("Previous day", systemImage: "chevron.left", enabled: model.canGoToPreviousDay) {
                model.previousDay()
            }
            VStack(spacing: 2) {
                Text(model.dateTitle)
                    .font(.headline)
                    .monospacedDigit()
                HStack(spacing: 6) {
                    Text(model.relativeDayTitle)
                    if model.isLoading {
                        ProgressView().controlSize(.mini)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            dayButton("Next day", systemImage: "chevron.right", enabled: model.canGoToNextDay) {
                model.nextDay()
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private func dayButton(_ title: String, systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .disabled(!enabled)
        .accessibilityLabel(title)
    }

    /// Info and location buttons under the date bar, so the Details sheet never covers them.
    private var controls: some View {
        VStack(spacing: 0) {
            roundButton("Info", systemImage: "info.circle") {
                if model.selected != nil {
                    showsInfoAfterDetails = true
                    model.select(nil)
                } else {
                    isInfoShown = true
                }
            }
            Divider().frame(width: 44)
            roundButton("Show my location", systemImage: model.showsUserLocation ? "location.fill" : "location") {
                model.select(nil)
                Task { await model.locateUser() }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .padding(.trailing, 12)
        .padding(.top, topBarBottom + 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        // `topBarBottom` is global, so only the vertical insets are dropped; side insets (a status bar or camera on the side) stay.
        .ignoresSafeArea(edges: .vertical)
        .overlay(alignment: .bottom) {
            if model.isDayLoaded && !model.isLoading && model.pharmacies.isEmpty && model.blocking == nil {
                Text("No duty pharmacies for this day")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        }
    }

    private func roundButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(title)
    }

    private var detailsShown: Binding<Bool> {
        Binding(
            get: { model.selected != nil },
            set: { if !$0 { model.select(nil) } }
        )
    }

    private func detailsDismissed() {
        sheetHeight = 0
        if showsInfoAfterDetails {
            showsInfoAfterDetails = false
            isInfoShown = true
        }
    }
}

private struct TopBarBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
