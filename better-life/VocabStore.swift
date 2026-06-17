import Foundation
import SwiftData
import Observation

/// What pool of words the current study session draws from.
enum SessionScope: Equatable {
    case smart           // due reviews across all words + a daily cap of new words
    case group(Int)      // only words in the given group (id)
    case review          // only words the user has marked 生 / 半熟
}

/// Aggregate progress for a slice of the word list.
struct GroupStats {
    var started: Int     // words with any progress (marked at least once)
    var learned: Int     // words marked 熟
    var total: Int

    var fraction: Double { total == 0 ? 0 : Double(learned) / Double(total) }
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

    /// How many never-seen words to introduce per session.
    var newPerDay = 20

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
        case .review:
            sessionQueue = reviewQueue()
        }

        plannedCount = sessionQueue.count
        reviewedThisSession = 0
        isRevealed = false
        undoStack.removeAll()     // new session → fresh undo history
    }

    /// Smart daily queue: due reviews (earliest first) + up to `newPerDay` new words.
    private func smartQueue() -> [VocabWord] {
        let today = currentDateString
        let progress = progressByWord
        let index = wordIndex
        let due = progress.values
            .filter { $0.needsReview && $0.dueDate <= today }
            .sorted { $0.dueDate < $1.dueDate }
            .compactMap { index[$0.word] }

        let new = allWords.lazy
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
}
