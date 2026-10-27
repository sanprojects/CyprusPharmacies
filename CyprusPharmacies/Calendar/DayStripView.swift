//
//  DayStripView.swift
//  CyprusPharmacies
//

import SwiftUI

/// A strip of days like the one in Apple's Home: a week in view, the chosen day marked. A swipe turns the strip as a drum
/// that clicks on each day and chooses nothing; a tap on a day chooses it. A tap on the chosen day opens the calendar,
/// a double tap goes back to today.
struct DayStripView: View {
    let days: [DutyCalendar.StripDay]
    let selectedOffset: Int
    /// "Today", "Tomorrow", … for VoiceOver on the chosen day.
    let relativeTitle: String
    let isLoading: Bool
    let onSelect: (Int) -> Void
    let onCalendar: () -> Void
    let onToday: () -> Void

    /// Odd, with `DutyCalendar.stripPadding` days on each side of the middle one.
    private static let visibleDays = CGFloat(2 * DutyCalendar.stripPadding + 1)
    /// The day in the middle of the strip: apart from `selectedOffset` while the strip is turned by hand.
    @State private var centered: Int?

    init(days: [DutyCalendar.StripDay], selectedOffset: Int, relativeTitle: String, isLoading: Bool,
         onSelect: @escaping (Int) -> Void, onCalendar: @escaping () -> Void, onToday: @escaping () -> Void) {
        self.days = days
        self.selectedOffset = selectedOffset
        self.relativeTitle = relativeTitle
        self.isLoading = isLoading
        self.onSelect = onSelect
        self.onCalendar = onCalendar
        self.onToday = onToday
        _centered = State(initialValue: selectedOffset)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width / Self.visibleDays
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(days) { day in cell(day, width: width) }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            .scrollPosition(id: $centered, anchor: .center)
        }
        .frame(height: 52)
        .onChange(of: selectedOffset) { _, offset in
            if centered != offset { withAnimation(.smooth) { centered = offset } }
        }
        .sensoryFeedback(.selection, trigger: centered)
    }

    private func cell(_ day: DutyCalendar.StripDay, width: CGFloat) -> some View {
        let isChosen = day.offset == selectedOffset
        let tint: Color = day.isInFeed ? .primary : Color(.tertiaryLabel)
        let content = VStack(spacing: 2) {
            Text(day.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isChosen ? .primary : day.isInFeed ? .secondary : tint)
            ZStack {
                if isChosen { Circle().fill(Color.accentColor) }
                if isChosen && isLoading {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Text("\(day.day)")
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isChosen ? Color.white : tint)
                }
            }
            .frame(width: 30, height: 30)
        }
        .frame(width: width, height: 52)
        .contentShape(Rectangle())
        .scrollTransition(axis: .horizontal) { content, phase in
            content.opacity(1 - abs(phase.value) * 0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
        return Group {
            if isChosen {
                // The double tap is declared first, so the single tap waits for it to fail.
                content
                    .onTapGesture(count: 2, perform: onToday)
                    .onTapGesture(perform: onCalendar)
                    .accessibilityLabel("\(day.label), \(relativeTitle)")
                    .accessibilityHint("Opens the calendar")
                    .accessibilityAction(named: "Today", onToday)
                    .accessibilityIdentifier("dayMenu")
            } else if day.isInFeed {
                content
                    .onTapGesture {
                        withAnimation(.smooth) { centered = day.offset }
                        onSelect(day.offset)
                    }
                    .accessibilityLabel(day.label)
            } else {
                content.accessibilityHidden(true)
            }
        }
    }
}
