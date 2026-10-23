//
//  MapScreen.swift
//  CyprusPharmacies
//

import SwiftUI
import UIKit

struct MapScreen: View {
    /// Sheets other than Details; only one sheet is up at a time.
    enum Sheet: String, Identifiable {
        case info
        case list
        var id: String { rawValue }
    }

    /// Map chrome stops growing here, so the date bar and buttons leave room for the map.
    private static let chromeTextLimit = DynamicTypeSize.xxxLarge
    private static let maxSheetFraction: CGFloat = 0.75

    @Bindable var model: MapViewModel

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var topBarBottom: CGFloat = 0
    @State private var sheetHeight: CGFloat = 0
    @State private var sheet: Sheet?
    /// Asked for while Details was up: shown once that sheet is gone.
    @State private var sheetAfterDetails: Sheet?
    /// Tapped in the list: selected once the list is gone.
    @State private var pharmacyAfterSheet: Pharmacy?
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
                        distance: model.distance(to: pharmacy),
                        onHeightChange: { height in
                            // Taller content scrolls inside a sheet capped at 3/4 of the screen.
                            sheetHeight = min(height, root.size.height * Self.maxSheetFraction)
                            model.focus(on: pharmacy, bottomInset: sheetHeight + root.safeAreaInsets.bottom)
                        },
                        onClose: { model.select(nil) }
                    )
                    .id(pharmacy.id)
                    .presentationDetents([.height(sheetHeight > 0 ? sheetHeight : 320)])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled)
                }
            }
        }
        .sheet(item: $sheet, onDismiss: sheetDismissed) { sheet in
            switch sheet {
            case .info:
                InfoView()
                    .presentationDetents([.medium, .large])
            case .list:
                PharmacyListView(
                    title: model.dateTitle,
                    pharmacies: model.sortedPharmacies,
                    isLoading: model.isLoading,
                    distance: { model.distance(to: $0) },
                    onSelect: { pharmacy in
                        pharmacyAfterSheet = pharmacy
                        self.sheet = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .task { await model.refreshUserLocation() }
            }
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
            dayMenu
            dayButton("Next day", systemImage: "chevron.right", enabled: model.canGoToNextDay) {
                model.nextDay()
            }
        }
        .padding(6)
        .glassBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .dynamicTypeSize(...Self.chromeTextLimit)
    }

    /// Tapping the date opens a menu of all days the feed has, instead of stepping with the arrows.
    private var dayMenu: some View {
        Menu {
            Picker("Day", selection: Binding(get: { model.offset }, set: { model.show(offset: $0) })) {
                ForEach(DutyCalendar.offsets, id: \.self) { offset in
                    Text(model.calendar.menuTitle(offset: offset)).tag(offset)
                }
            }
        } label: {
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
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        // Plain style keeps the date in label colors instead of the accent color.
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint("Choose another day")
        .accessibilityIdentifier("dayMenu")
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
            roundButton("Info", systemImage: "info.circle") { show(.info) }
            Divider().frame(width: 44)
            roundButton("List of pharmacies", systemImage: "list.bullet") { show(.list) }
            Divider().frame(width: 44)
            roundButton("Show my location", systemImage: model.showsUserLocation ? "location.fill" : "location") {
                model.select(nil)
                Task { await model.locateUser() }
            }
        }
        .glassBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true)
        .dynamicTypeSize(...Self.chromeTextLimit)
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
                    .glassBackground(in: Capsule())
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

    /// Two sheets cannot be up together: Details goes away first.
    private func show(_ next: Sheet) {
        if model.selected != nil {
            sheetAfterDetails = next
            model.select(nil)
        } else {
            sheet = next
        }
    }

    private func detailsDismissed() {
        sheetHeight = 0
        if let next = sheetAfterDetails {
            sheetAfterDetails = nil
            sheet = next
        }
    }

    private func sheetDismissed() {
        if let pharmacy = pharmacyAfterSheet {
            pharmacyAfterSheet = nil
            model.select(pharmacy, zoomIn: true)
        }
    }
}

private struct TopBarBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
