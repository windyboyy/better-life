import Foundation
import SwiftData
import Observation

/// What pool of words the current study session draws from.
enum SessionScope: Equatable {
    case smart                        // due reviews + daily cap of new words (plan-scoped)
    case group(Int)                   // only words in the given group (id)
    case difficulty(VocabDifficulty)  // all words of a given difficulty tier
    case review                       // only words the user has marked 生 / 半熟
}

/// Aggregate progress for a slice of the word list.
struct GroupStats {
    var started: Int     // words with any progress (marked at least once)
    var learned: Int     // words marked 熟
    var total: Int

    var fraction: Double { total == 0 ? 0 : Double(learned) / Double(total) }
}

// MARK: - Study Plan

/// User-chosen study plan — which difficulty tier to focus on.
/// Persisted in UserDefaults so it survives app restarts.
enum StudyPlan: String, CaseIterable {
    case core = "核心"
    case common = "常用"
    case advanced = "进阶"

    var difficulty: VocabDifficulty {
        switch self {
        case .core: return .core
        case .common: return .common
        case .advanced: return .advanced
        }
    }

    var color: String {
        switch self {
        case .core: return "core"
        case .common: return "common"
        case .advanced: return "advanced"
        }
    }

    /// SF Symbol for the plan badge.
    var iconName: String {
        switch self {
        case .core: return "flame.fill"
        case .common: return "star.fill"
        case .advanced: return "sparkles"
        }
    }
}

/// Drives the flashcard study session: loads the bundled word list, tracks
/// per-word marks in SwiftData, and builds each session's queue from a chosen
/// scope (smart daily learning, a specific group, or review of marked words).
@Observable
final class VocabStore {
    private let modelContext: ModelContext

    /// Full read-only dictionary, ordered by study importance (most useful first).
    let allWords: [VocabWord]
    /// Fixed-size, importance-ordered study groups derived from `allWords`.
    let groups: [VocabGroup]
    private let wordIndex: [String: VocabWord]

    /// Words pre-filtered by difficulty tier, for plan-based queries.
    private let wordsByDifficulty: [VocabDifficulty: [VocabWord]]

    /// How many never-seen words to introduce per session.
    var newPerDay = 20

    // MARK: - Study plan

    /// The user's active study plan. Persisted to UserDefaults.
    var selectedPlan: StudyPlan {
        didSet {
            UserDefaults.standard.set(selectedPlan.rawValue, forKey: "selectedPlan")
            // When plan changes and smart session was active, rebuild it.
            if case .smart = currentScope { startSession(.smart) }
        }
    }

    /// All words that belong to the currently selected plan, in importance order.
    var planWords: [VocabWord] {
        wordsByDifficulty[selectedPlan.difficulty] ?? []
    }

    /// Cached per-word progress, refreshed from SwiftData. Drives stats without
    /// hitting the store on every view render.
    private(set) var progressByWord: [String: WordProgress] = [:]

    /// The remaining words to study in this session, front = current.
    private(set) var sessionQueue: [VocabWord] = []
    /// Whether the answer (translation) is currently revealed for the front card.
    private(set) var isRevealed = false

    /// Session counters for the progress display.
    private(set) var reviewedThisSession = 0
    private(set) var plannedCount = 0

    /// The scope the current session was built from (drives "再来一组").
    private(set) var currentScope: SessionScope = .smart

    private var currentDateString = ""

    // MARK: - Undo

    /// Snapshot of a word's progress before a mark was applied, so the mark can
    /// be precisely reversed.
    private struct MarkUndo {
        let word: VocabWord
        let wasNewlyCreated: Bool       // true → mark() created a new WordProgress row
        let prevMarkRaw: Int
        let prevDueDate: String
        let prevReviewCount: Int
        let prevLastReviewed: Date?
        let wasRequeued: Bool           // true → review mode appended word to queue tail
    }

    private var undoStack: [MarkUndo] = []
    var canUndo: Bool { !undoStack.isEmpty }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.allWords = VocabLoader.loadBundled()
        self.groups = VocabLoader.makeGroups(from: allWords)
        self.wordIndex = Dictionary(uniqueKeysWithValues: allWords.map { ($0.word, $0) })
        // Pre-index by difficulty for fast plan filtering.
        self.wordsByDifficulty = Dictionary(grouping: allWords) { $0.difficulty }
        // Restore persisted plan, default to 核心.
        let raw = UserDefaults.standard.string(forKey: "selectedPlan") ?? StudyPlan.core.rawValue
        self.selectedPlan = StudyPlan(rawValue: raw) ?? .core
        reloadProgress()
        startSession(.smart)
    }

    // MARK: - Session lifecycle

    /// (Re)build the session queue for a scope.
    func startSession(_ scope: SessionScope) {
        currentScope = scope
        currentDateString = DateHelper.todayString()
        reloadProgress()

        switch scope {
        case .smart:
            sessionQueue = smartQueue()
        case .group(let id):
            sessionQueue = groupQueue(id)
        case .difficulty(let difficulty):
            sessionQueue = difficultyQueue(difficulty)
        case .review:
            sessionQueue = reviewQueue()
        }

        plannedCount = sessionQueue.count
        reviewedThisSession = 0
        isRevealed = false
        undoStack.removeAll()     // new session → fresh undo history
    }

    /// Smart daily queue: due reviews (earliest first) + up to `newPerDay` new words.
    /// Scoped to the user's currently selected study plan.
    private func smartQueue() -> [VocabWord] {
        let today = currentDateString
        let progress = progressByWord
        let planWordSet = Set(planWords.map { $0.word })
        let index = wordIndex

        let due = progress.values
            .filter { prog in
                prog.needsReview
                    && prog.dueDate <= today
                    && planWordSet.contains(prog.word)
            }
            .sorted { $0.dueDate < $1.dueDate }
            .compactMap { index[$0.word] }

        let new = planWords.lazy
            .filter { progress[$0.word] == nil }
            .prefix(newPerDay)
            .map { $0 }

        return due + Array(new)
    }

    /// Group queue: due words in the group + up to `newPerDay` unstudied words
    /// from the group, all in the group's own order.
    private func groupQueue(_ id: Int) -> [VocabWord] {
        guard let group = groups.first(where: { $0.id == id }) else { return [] }
        let today = currentDateString

        var due: [VocabWord] = []
        var new: [VocabWord] = []
        for word in group.words {
            if let p = progressByWord[word.word] {
                if p.needsReview && p.dueDate <= today { due.append(word) }
            } else if new.count < newPerDay {
                new.append(word)
            }
        }
        return due + new
    }

    /// Difficulty-tier queue: due reviews in the tier + up to `newPerDay` unstudied
    /// words from the same tier, in importance order.
    private func difficultyQueue(_ difficulty: VocabDifficulty) -> [VocabWord] {
        let today = currentDateString
        let words = wordsByDifficulty[difficulty] ?? []

        var due: [VocabWord] = []
        var new: [VocabWord] = []
        for word in words {
            if let p = progressByWord[word.word] {
                if p.needsReview && p.dueDate <= today { due.append(word) }
            } else if new.count < newPerDay {
                new.append(word)
            }
        }
        return due + new
    }

    /// Review queue: every word currently marked 生 / 半熟, 生 first, then by how
    /// long since it was last seen. Ignores the due date — review is on demand.
    private func reviewQueue() -> [VocabWord] {
        let index = wordIndex
        return progressByWord.values
            .filter { $0.needsReview }
            .sorted {
                if $0.markRaw != $1.markRaw { return $0.markRaw < $1.markRaw } // 生(1) before 半熟(2)
                return ($0.lastReviewed ?? .distantPast) < ($1.lastReviewed ?? .distantPast)
            }
            .compactMap { index[$0.word] }
    }

    /// Re-roll a smart session if the calendar day changed while backgrounded.
    func refreshIfDateChanged() {
        if DateHelper.todayString() != currentDateString {
            startSession(.smart)
        } else {
            reloadProgress()
        }
    }

    // MARK: - Current card

    var currentWord: VocabWord? { sessionQueue.first }
    var isSessionDone: Bool { sessionQueue.isEmpty }

    func reveal() { isRevealed = true }

    /// The current word's existing mark, if any (for showing its decoration).
    func mark(for word: VocabWord) -> WordMark {
        progressByWord[word.word]?.mark ?? .unmarked
    }

    /// Record a mark for the current card and advance. In review mode a word that
    /// stays 生 / 半熟 is re-queued so it comes back later in the same session;
    /// marking it 熟 retires it from the session.
    func mark(_ newMark: WordMark) {
        guard let word = sessionQueue.first else { return }
        let today = currentDateString
        let wasRequeued = currentScope == .review && newMark != .familiar

        // Snapshot state before mutation so undo can restore it exactly.
        let progress: WordProgress
        if let existing = progressByWord[word.word] {
            undoStack.append(MarkUndo(
                word: word, wasNewlyCreated: false,
                prevMarkRaw: existing.markRaw, prevDueDate: existing.dueDate,
                prevReviewCount: existing.reviewCount, prevLastReviewed: existing.lastReviewed,
                wasRequeued: wasRequeued))
            progress = existing
        } else {
            progress = WordProgress(word: word.word, dueDate: today)
            modelContext.insert(progress)
            progressByWord[word.word] = progress
            undoStack.append(MarkUndo(
                word: word, wasNewlyCreated: true,
                prevMarkRaw: WordMark.unmarked.rawValue, prevDueDate: today,
                prevReviewCount: 0, prevLastReviewed: nil,
                wasRequeued: wasRequeued))
        }
        progress.setMark(newMark, today: today)
        try? modelContext.save()

        sessionQueue.removeFirst()
        if wasRequeued {
            sessionQueue.append(word)   // keep cycling until it's marked 熟
        }
        reviewedThisSession += 1
        isRevealed = false
    }

    /// Reverse the most recent mark. Restores SwiftData state, re-inserts the word
    /// at the front of the session queue, decrements the session counter, and
    /// reveals the card so the user can re-grade immediately.
    func undoLastMark() {
        guard let snapshot = undoStack.popLast() else { return }
        let word = snapshot.word

        if snapshot.wasNewlyCreated {
            if let progress = progressByWord[word.word] {
                modelContext.delete(progress)
                progressByWord.removeValue(forKey: word.word)
            }
        } else {
            if let progress = progressByWord[word.word] {
                progress.markRaw = snapshot.prevMarkRaw
                progress.dueDate = snapshot.prevDueDate
                progress.reviewCount = snapshot.prevReviewCount
                progress.lastReviewed = snapshot.prevLastReviewed
            }
        }
        try? modelContext.save()

        // Restore queue: remove the re-queued copy (if any), then put word back at front.
        if snapshot.wasRequeued, let idx = sessionQueue.lastIndex(of: word) {
            sessionQueue.remove(at: idx)
        }
        sessionQueue.insert(word, at: 0)

        reviewedThisSession = max(0, reviewedThisSession - 1)
        isRevealed = true
    }

    // MARK: - Stats

    private func reloadProgress() {
        let list = (try? modelContext.fetch(FetchDescriptor<WordProgress>())) ?? []
        progressByWord = Dictionary(uniqueKeysWithValues: list.map { ($0.word, $0) })
    }

    var learnedCount: Int { progressByWord.values.filter { $0.isLearned }.count }
    var startedCount: Int { progressByWord.count }
    var totalWords: Int { allWords.count }

    /// Words not yet introduced.
    var remainingCount: Int { max(0, totalWords - startedCount) }

    // MARK: Plan-specific stats

    /// Total words in the current plan.
    var planTotalWords: Int { planWords.count }

    /// Words in the current plan that have been started.
    var planStartedCount: Int {
        let set = Set(planWords.map { $0.word })
        return progressByWord.values.filter { set.contains($0.word) }.count
    }

    /// Words in the current plan marked 熟.
    var planLearnedCount: Int {
        let set = Set(planWords.map { $0.word })
        return progressByWord.values.filter { $0.isLearned && set.contains($0.word) }.count
    }

    /// Unstarted words remaining in the current plan.
    var planRemainingCount: Int { max(0, planTotalWords - planStartedCount) }

    /// Plan progress fraction.
    var planFraction: Double {
        planTotalWords == 0 ? 0 : Double(planLearnedCount) / Double(planTotalWords)
    }

    /// Stats for one group, computed from the cached progress snapshot.
    func stats(for group: VocabGroup) -> GroupStats {
        var started = 0, learned = 0
        for word in group.words {
            if let p = progressByWord[word.word] {
                started += 1
                if p.isLearned { learned += 1 }
            }
        }
        return GroupStats(started: started, learned: learned, total: group.words.count)
    }

    /// Stats for a difficulty tier, used in the browse view.
    func statsForDifficulty(_ difficulty: VocabDifficulty) -> GroupStats {
        let words = wordsByDifficulty[difficulty] ?? []
        var started = 0, learned = 0
        for word in words {
            if let p = progressByWord[word.word] {
                started += 1
                if p.isLearned { learned += 1 }
            }
        }
        return GroupStats(started: started, learned: learned, total: words.count)
    }

    /// Words currently in the review pool (生 / 半熟), 生 first.
    var reviewWords: [VocabWord] {
        let index = wordIndex
        return progressByWord.values
            .filter { $0.needsReview }
            .sorted {
                if $0.markRaw != $1.markRaw { return $0.markRaw < $1.markRaw }
                return ($0.lastReviewed ?? .distantPast) < ($1.lastReviewed ?? .distantPast)
            }
            .compactMap { index[$0.word] }
    }

    var reviewCount: Int { progressByWord.values.filter { $0.needsReview }.count }
    var rawCount: Int { progressByWord.values.filter { $0.mark == .raw }.count }
    var halfCount: Int { progressByWord.values.filter { $0.mark == .half }.count }

    // MARK: - Finish estimate

    /// Days to introduce every remaining word at `perDay` new words a day.
    func daysToFinish(perDay: Int) -> Int {
        guard perDay > 0, remainingCount > 0 else { return 0 }
        return Int((Double(remainingCount) / Double(perDay)).rounded(.up))
    }

    /// Calendar date by which all words would be introduced at `perDay` a day.
    func finishDate(perDay: Int) -> Date? {
        let days = daysToFinish(perDay: perDay)
        guard days > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: Date())
    }

    /// Plan-aware: days to finish introducing remaining words in the current plan.
    func planDaysToFinish(perDay: Int) -> Int {
        guard perDay > 0, planRemainingCount > 0 else { return 0 }
        return Int((Double(planRemainingCount) / Double(perDay)).rounded(.up))
    }

    /// Plan-aware: calendar date for finishing the current plan.
    func planFinishDate(perDay: Int) -> Date? {
        let days = planDaysToFinish(perDay: perDay)
        guard days > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: Date())
    }
}
