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
        case calendar
        var id: String { rawValue }
    }

    /// Map chrome stops growing here, so the date bar and buttons leave room for the map.
    private static let chromeTextLimit = DynamicTypeSize.xxxLarge
    private static let maxSheetFraction: CGFloat = 0.75
    /// On a wide iPad window the date bar stays phone-sized, centered, clear of the window controls.
    private static let topBarMaxWidth: CGFloat = 440

    @Bindable var model: MapViewModel

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var topBarBottom: CGFloat = 0
    @State private var sheetHeight: CGFloat = 0
    @State private var calendarHeight: CGFloat = 0
    @State private var sheet: Sheet?
    /// Asked for while Details was up: shown once that sheet is gone.
    @State private var sheetAfterDetails: Sheet?
    /// Tapped in the list: selected once the list is gone.
    @State private var pharmacyAfterSheet: Pharmacy?
    @State private var hasStarted = false
    /// When a finger last moved sideways over the date bar: the touch that ends such a swipe is not a tap on a button.
    @State private var swipedAt = Date.distantPast

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
                    .frame(maxWidth: Self.topBarMaxWidth)
                    .padding(.horizontal, 12)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: TopBarBottomKey.self, value: proxy.frame(in: .global).maxY)
                    })

                if model.blocking == .failure {
                    LoadFailureView { model.dismissFailure() }
                }
            }
            .onPreferenceChange(TopBarBottomKey.self) { topBarBottom = $0 }
            // A tick for a pharmacy picked on the map or in the list, a lighter one when its panel goes away.
            .sensoryFeedback(trigger: model.selected?.id) { _, new in
                new == nil ? .impact(weight: .light) : .selection
            }
            .onChange(of: model.selected?.id) { _, _ in
                // Another pin with a sheet of the same height reports no new height: focus it here.
                if let pharmacy = model.selected, sheetHeight > 0 {
                    model.focus(on: pharmacy, bottomInset: sheetHeight)
                }
            }
            .sheet(isPresented: detailsShown, onDismiss: detailsDismissed) {
                if let pharmacy = model.selected {
                    // The sheet's height adds the bottom safe area to the detent; Details ignores it, so it is taken off here.
                    PharmacyDetailsView(
                        pharmacy: pharmacy,
                        distance: model.distance(to: pharmacy),
                        userCoordinate: model.userLocation?.coordinate,
                        onHeightChange: { height in
                            // Taller content scrolls inside a sheet capped at 3/4 of the screen.
                            withAnimation(.smooth) { sheetHeight = min(height, root.size.height * Self.maxSheetFraction) }
                            model.focus(on: pharmacy, bottomInset: sheetHeight)
                        },
                        onClose: { model.select(nil) }
                    )
                    .presentationDetents([.height(sheetHeight > 0 ? max(0, sheetHeight - root.safeAreaInsets.bottom) : 320)])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled)
                    .clearSheetBackground()
                }
            }
        }
        .sheet(item: $sheet, onDismiss: sheetDismissed) { sheet in
            switch sheet {
            case .info:
                InfoView()
                    .presentationDetents([.medium, .large])
            case .calendar:
                DayCalendarView(
                    months: model.calendar.months(),
                    selectedOffset: model.offset,
                    hasPharmacies: { model.hasPharmacies(offset: $0) },
                    onSelect: { offset in
                        model.show(offset: offset)
                        self.sheet = nil
                    },
                    onHeightChange: { calendarHeight = $0 }
                )
                .presentationDetents(calendarHeight > 0 ? [.height(calendarHeight), .large] : [.large])
                .clearSheetBackground()
            case .list:
                PharmacyListView(
                    title: model.dateTitle,
                    pharmacies: model.sortedPharmacies,
                    isLoading: model.isLoading,
                    distance: { model.distance(to: $0) },
                    userCoordinate: model.userLocation?.coordinate,
                    onSelect: { pharmacy in
                        pharmacyAfterSheet = pharmacy
                        self.sheet = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .clearSheetBackground()
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
        // The duty day changes at 08:00, not at midnight.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(1, model.calendar.nextDayStart.timeIntervalSinceNow)))
                if hasStarted { model.refreshIfNeeded() }
            }
        }
    }

    private var map: some View {
        PharmacyMapView(
            pharmacies: model.pharmacies,
            selected: model.selected,
            command: model.mapCommand,
            showsUserLocation: model.showsUserLocation,
            topInset: topBarBottom,
            onSelect: { model.select($0) },
            onUserMove: { model.userDidMoveMap() }
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
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // A swipe along the bar turns the day, as the arrows do: left for the next day, right for the previous one.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
            .onChanged { _ in swipedAt = Date() }
            .onEnded { value in
                swipedAt = Date()
                let across = value.translation.width, along = value.translation.height
                guard abs(across) > 50, abs(across) > abs(along) * 1.5 else { return }
                if across < 0 { model.nextDay() } else { model.previousDay() }
            }
        )
        .animation(.smooth, value: model.offset)
        .animation(.smooth, value: model.isLoading)
        .sensoryFeedback(.selection, trigger: model.offset)
    }

    /// Tapping the date opens a calendar of the days the feed covers, with the days that have pharmacies marked; a double tap goes back to today.
    private var dayMenu: some View {
        VStack(spacing: 2) {
            Text(model.dateTitle)
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
            HStack(spacing: 6) {
                Text(model.relativeDayTitle)
                    .contentTransition(.numericText())
                if model.isLoading {
                    ProgressView().controlSize(.mini).transition(.opacity)
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
        // The double tap is declared first, so the single tap waits for it to fail.
        .onTapGesture(count: 2) {
            guard !isSwiping else { return }
            model.showToday()
        }
        .onTapGesture {
            guard !isSwiping else { return }
            show(.calendar)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits([.isHeader, .isButton])
        .accessibilityHint("Opens the calendar")
        .accessibilityAction(named: "Today") { model.showToday() }
        .accessibilityIdentifier("dayMenu")
    }

    private var isSwiping: Bool { Date().timeIntervalSince(swipedAt) < 0.4 }

    private func dayButton(_ title: String, systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { if !isSwiping { action() } } label: {
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
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.smooth, value: model.isDayLoaded && !model.isLoading && model.pharmacies.isEmpty && model.blocking == nil)
    }

    private func roundButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .contentTransition(.symbolEffect(.replace))
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
