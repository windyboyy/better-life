import Foundation
import SwiftData
import Observation

@Observable
final class HabitStore {
    private let modelContext: ModelContext
    private(set) var todayRecord: DailyRecord?
    private(set) var records: [DailyRecord] = []
    private var currentDateString: String = ""

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    func refresh() {
        let today = DateHelper.todayString()
        currentDateString = today
        fetchTodayRecord(for: today)
        fetchAllRecords()
    }

    /// Check if the date has changed (e.g. past midnight) and refresh if needed
    func checkDateChange() {
        let today = DateHelper.todayString()
        if today != currentDateString {
            refresh()
        }
    }

    private func fetchTodayRecord(for dateString: String) {
        let descriptor = FetchDescriptor<DailyRecord>(
            predicate: #Predicate { $0.dateString == dateString }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            todayRecord = existing
        } else {
            let record = DailyRecord(dateString: dateString)
            modelContext.insert(record)
            try? modelContext.save()
            todayRecord = record
        }
    }

    private func fetchAllRecords() {
        let descriptor = FetchDescriptor<DailyRecord>(
            sortBy: [SortDescriptor(\.dateString, order: .reverse)]
        )
        records = (try? modelContext.fetch(descriptor)) ?? []
    }

    func toggleExercise() {
        guard let record = todayRecord else { return }
        record.exerciseDone.toggle()
        try? modelContext.save()
        fetchAllRecords()
    }

    func toggleReading() {
        guard let record = todayRecord else { return }
        record.readingDone.toggle()
        try? modelContext.save()
        fetchAllRecords()
    }

    // MARK: - Stats

    var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = Date()

        // If today is not allDone, start counting from yesterday
        if todayRecord?.allDone != true {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                return 0
            }
            checkDate = yesterday
        }

        let recordMap = Dictionary(uniqueKeysWithValues: records.map { ($0.dateString, $0) })

        while true {
            let dateStr = DateHelper.stringFromDate(checkDate)
            if let record = recordMap[dateStr], record.allDone {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prev
            } else {
                break
            }
        }
        return streak
    }

    var totalCompletedDays: Int {
        records.filter { $0.allDone }.count
    }

    func recordsForMonth(year: Int, month: Int) -> [String: DailyRecord] {
        let prefix = String(format: "%04d-%02d", year, month)
        let monthRecords = records.filter { $0.dateString.hasPrefix(prefix) }
        return Dictionary(uniqueKeysWithValues: monthRecords.map { ($0.dateString, $0) })
    }
}
