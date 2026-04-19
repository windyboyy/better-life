import Foundation
import SwiftData

@Model
final class DailyRecord {
    #Unique<DailyRecord>([\.dateString])

    var dateString: String
    var exerciseDone: Bool
    var readingDone: Bool
    var exerciseTime: Date?
    var readingTime: Date?

    init(dateString: String, exerciseDone: Bool = false, readingDone: Bool = false) {
        self.dateString = dateString
        self.exerciseDone = exerciseDone
        self.readingDone = readingDone
        self.exerciseTime = nil
        self.readingTime = nil
    }

    var allDone: Bool { exerciseDone && readingDone }
    var anyDone: Bool { exerciseDone || readingDone }
}
