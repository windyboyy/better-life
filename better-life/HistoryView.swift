import SwiftUI
import SwiftData

struct HistoryView: View {
    var store: HabitStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Stats banner
                    HStack(spacing: 12) {
                        StatCard(
                            icon: "flame.fill",
                            value: store.currentStreak,
                            label: "连续完成",
                            color: .blue
                        )
                        StatCard(
                            icon: "star.fill",
                            value: store.totalCompletedDays,
                            label: "累计完成",
                            color: .blue
                        )
                    }
                    .padding(.top, 8)

                    // Calendar
                    CalendarGridView(store: store)

                    // Recent records
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.blue)
                            Text("最近记录")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 4)

                        let recentRecords = Array(store.records.prefix(7))
                        if recentRecords.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.tertiary)
                                Text("暂无记录")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else {
                            ForEach(recentRecords, id: \.dateString) { record in
                                RecentRecordRow(record: record)
                                if record.dateString != recentRecords.last?.dateString {
                                    Divider()
                                        .padding(.leading, 4)
                                }
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
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.03), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("历史")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct StatCard: View {
    let icon: String
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)

            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }
}

private struct RecentRecordRow: View {
    let record: DailyRecord

    private var isAllDone: Bool {
        record.exerciseDone && record.readingDone
    }

    var body: some View {
        HStack(spacing: 12) {
            // Date
            VStack(alignment: .leading, spacing: 2) {
                Text(DateHelper.displayDate(record.dateString))
                    .font(.system(size: 15, weight: .medium))
            }

            Spacer()

            // Status badges
            HStack(spacing: 8) {
                HabitBadge(
                    icon: "figure.run",
                    isDone: record.exerciseDone,
                    color: .orange
                )
                HabitBadge(
                    icon: "book.fill",
                    isDone: record.readingDone,
                    color: .blue
                )
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HabitBadge: View {
    let icon: String
    let isDone: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Image(systemName: isDone ? "checkmark" : "xmark")
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(isDone ? color.opacity(0.15) : Color.gray.opacity(0.1))
        )
        .foregroundStyle(isDone ? color : .gray)
    }
}

#Preview {
    let container = try! ModelContainer(for: DailyRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    HistoryView(store: HabitStore(modelContext: container.mainContext))
}
