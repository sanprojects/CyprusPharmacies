//
//  DayCalendarView.swift
//  CyprusPharmacies
//

import SwiftUI

/// The days the feed covers as a month grid; a dot marks the days with duty pharmacies, a tap shows the day.
struct DayCalendarView: View {
    let months: [DutyCalendar.Month]
    let selectedOffset: Int
    let hasPharmacies: (Int) -> Bool
    let onSelect: (Int) -> Void
    /// The natural height of the content, so the sheet can fit it.
    let onHeightChange: (CGFloat) -> Void

    @Environment(\.dismiss) private var dismiss
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(months, id: \.title) { month in
                        monthView(month)
                    }
                    legend
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: CalendarHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(CalendarHeightKey.self) { onHeightChange($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .sheetGlass()
    }

    private var header: some View {
        HStack(spacing: 12) {
            // Keeps the title centered against Close.
            Color.clear.frame(width: 44, height: 44)
            Text("Choose a day")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity)
            Button { dismiss() } label: {
                CircleButtonLabel(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func monthView(_ month: DutyCalendar.Month) -> some View {
        VStack(spacing: 8) {
            Text(month.title)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(DutyCalendar.weekdayTitles, id: \.self) { title in
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                ForEach(Array(month.cells.enumerated()), id: \.offset) { _, cell in
                    if let cell {
                        dayCell(cell)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ cell: DutyCalendar.Cell) -> some View {
        if let offset = cell.offset {
            let marked = hasPharmacies(offset)
            let selected = offset == selectedOffset
            Button {
                onSelect(offset)
            } label: {
                VStack(spacing: 3) {
                    Text("\(cell.day)")
                        .font(.body.weight(selected ? .bold : .regular))
                        .monospacedDigit()
                    Circle()
                        .fill(marked ? (selected ? Color.white : Color.accentColor) : Color.clear)
                        .frame(width: 6, height: 6)
                }
                .foregroundStyle(selected ? Color.white : Color(.label))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if selected { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.tint) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(cell.day), \(marked ? "pharmacies on duty" : "no pharmacies")")
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            Text("\(cell.day)")
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityHidden(true)
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.accentColor).frame(width: 8, height: 8)
            Text("Duty pharmacies listed")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

private struct CalendarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
