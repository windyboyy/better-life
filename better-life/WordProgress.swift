import Foundation
import SwiftData

/// The user's manual familiarity tag for a word — the single source of truth for
/// study state. Replaces the old correct/wrong grading.
///
/// - `.raw` (生)   → drawn with a circle, reviewed most often
/// - `.half` (半熟) → drawn with an underline, reviewed occasionally
/// - `.familiar` (熟) → no decoration, dropped from review
enum WordMark: Int, Codable, CaseIterable, Identifiable {
    case unmarked = 0   // seen but not yet tagged (transient; user always picks one)
    case raw = 1
    case half = 2
    case familiar = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .unmarked: return "未标"
        case .raw: return "生"
        case .half: return "半熟"
        case .familiar: return "熟"
        }
    }

    /// Days until this word is due again after being given this mark.
    /// 生 comes back tomorrow, 半熟 in a few days, 熟 effectively retires.
    var intervalDays: Int {
        switch self {
        case .unmarked, .raw: return 1
        case .half: return 4
        case .familiar: return 365
        }
    }
}

/// Per-word study state, persisted in SwiftData. A row only exists once the user
/// has marked that word at least once — unmarked words live only in the bundled
/// `VocabWord` list, so we never seed 5000+ rows up front.
@Model
final class WordProgress {
    #Unique<WordProgress>([\.word])

    var word: String          // matches VocabWord.word
    var markRaw: Int = 0      // backing store for `mark`; default lets existing rows migrate
    var dueDate: String       // yyyy-MM-dd: next day this word is due for review
    var reviewCount: Int = 0
    var lastReviewed: Date?

    init(word: String, mark: WordMark = .unmarked, dueDate: String) {
        self.word = word
        self.markRaw = mark.rawValue
        self.dueDate = dueDate
        self.reviewCount = 0
        self.lastReviewed = nil
    }

    /// Typed accessor over the stored `markRaw`.
    var mark: WordMark {
        get { WordMark(rawValue: markRaw) ?? .unmarked }
        set { markRaw = newValue.rawValue }
    }

    /// Apply a mark and reschedule the next review from `today` (yyyy-MM-dd).
    func setMark(_ newMark: WordMark, today: String) {
        mark = newMark
        reviewCount += 1
        lastReviewed = Date()

        let days = newMark.intervalDays
        if let todayDate = DateHelper.dateFromString(today),
           let next = Calendar.current.date(byAdding: .day, value: days, to: todayDate) {
            dueDate = DateHelper.stringFromDate(next)
        } else {
            dueDate = today
        }
    }

    /// A word counts as learned once marked 熟.
    var isLearned: Bool { mark == .familiar }

    /// In the review pool while marked 生 or 半熟.
    var needsReview: Bool { mark == .raw || mark == .half }
}
