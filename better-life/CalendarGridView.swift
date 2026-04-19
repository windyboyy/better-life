import SwiftUI

struct CalendarGridView: View {
    var store: HabitStore
    @State private var displayedYear: Int
    @State private var displayedMonth: Int

    init(store: HabitStore) {
        self.store = store
        let calendar = Calendar.current
        let now = Date()
        _displayedYear = State(initialValue: calendar.component(.year, from: now))
        _displayedMonth = State(initialValue: calendar.component(.month, from: now))
    }

    private var isCurrentMonth: Bool {
        let calendar = Calendar.current
        let now = Date()
        return displayedYear == calendar.component(.year, from: now)
            && displayedMonth == calendar.component(.month, from: now)
    }

    private var monthTitle: String {
        "\(displayedYear)年\(displayedMonth)月"
    }

    var body: some View {
        VStack(spacing: 16) {
            // Month navigation
            HStack {
                Button(action: goToPreviousMonth) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue.opacity(0.7))
                }

                Spacer()

                Text(monthTitle)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))

                Spacer()

                Button(action: goToNextMonth) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue.opacity(isCurrentMonth ? 0.2 : 0.7))
                }
                .disabled(isCurrentMonth)
            }
            .padding(.horizontal, 4)

            // Weekday headers
            let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Day cells
            let days = DateHelper.daysInMonth(year: displayedYear, month: displayedMonth)
            let offset = DateHelper.weekdayOffset(year: displayedYear, month: displayedMonth)
            let recordMap = store.recordsForMonth(year: displayedYear, month: displayedMonth)
            let todayStr = DateHelper.todayString()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                // Empty cells for offset
                ForEach(0..<offset, id: \.self) { _ in
                    Color.clear
                        .frame(height: 38)
                }

                ForEach(days, id: \.self) { dateString in
                    let record = recordMap[dateString]
                    let isFuture = dateString > todayStr
                    let isToday = dateString == todayStr

                    DayCell(
                        day: String(Int(dateString.suffix(2))!),
                        allDone: record?.allDone ?? false,
                        anyDone: record?.anyDone ?? false,
                        isFuture: isFuture,
                        isToday: isToday
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        )
    }

    private func goToPreviousMonth() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if displayedMonth == 1 {
                displayedMonth = 12
                displayedYear -= 1
            } else {
                displayedMonth -= 1
            }
        }
    }

    private func goToNextMonth() {
        guard !isCurrentMonth else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            if displayedMonth == 12 {
                displayedMonth = 1
                displayedYear += 1
            } else {
                displayedMonth += 1
            }
        }
    }
}

private struct DayCell: View {
    let day: String
    let allDone: Bool
    let anyDone: Bool
    let isFuture: Bool
    let isToday: Bool

    private var textColor: Color {
        if isFuture { return .gray.opacity(0.3) }
        if allDone { return .white }
        if anyDone { return .white }
        return .primary.opacity(0.7)
    }

    var body: some View {
        ZStack {
            // Base background
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isFuture ? Color.clear : Color.gray.opacity(0.1))

            if allDone {
                // Full green
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green)
            } else if anyDone {
                // Left half green
                HStack(spacing: 0) {
                    Color.green
                    Color.clear
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Text(day)
                .font(.system(size: 13, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundColor(textColor)

            // Today indicator: small dot at the bottom
            if isToday && !allDone && !anyDone {
                VStack {
                    Spacer()
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                        .padding(.bottom, 4)
                }
            }
        }
        .frame(width: 38, height: 38)
    }
}
