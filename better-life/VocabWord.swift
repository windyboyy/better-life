import Foundation

/// A single IELTS dictionary entry, loaded read-only from the bundled
/// `ielts_words.json`. This is reference data — it never changes, so it lives in
/// the app bundle rather than SwiftData. Per-user review state is tracked
/// separately in `WordProgress`.
struct VocabWord: Codable, Identifiable, Hashable {
    let word: String
    let phonetic: String
    let translation: String   // Chinese gloss, may contain "\n" between senses
    let pos: String
    let collins: Int          // Collins star rating 0–5 (higher = more common)
    let oxford: Int           // in Oxford basic 3000 (0/1)
    let bnc: Int              // BNC frequency rank (0 = unknown)
    let frq: Int              // contemporary corpus rank (0 = unknown)

    var id: String { word }

    /// Translation split into individual sense lines for display.
    var senseLines: [String] {
        translation
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

extension VocabWord {
    /// Sort key for study order. Higher Collins stars come first (most useful
    /// words), then better corpus frequency, then BNC rank. Words with no rank
    /// (0) sink to the bottom of their tier rather than the top.
    var importanceKey: (Int, Int, Int) {
        let f = frq == 0 ? Int.max : frq
        let b = bnc == 0 ? Int.max : bnc
        return (-collins, f, b)
    }
}

/// A fixed-size, importance-ordered slice of the word list — the unit the user
/// picks to study ("第 1 组", "第 2 组" …). Groups are derived deterministically
/// from the sorted word list, so they need no persistence of their own.
struct VocabGroup: Identifiable, Hashable {
    let id: Int            // 0-based index in the ordered group list
    let words: [VocabWord]

    var number: Int { id + 1 }
    var displayName: String { "第 \(number) 组" }

    /// Average Collins star rating across the group, used for the difficulty badge.
    var averageCollins: Double {
        guard !words.isEmpty else { return 0 }
        return Double(words.reduce(0) { $0 + $1.collins }) / Double(words.count)
    }

    /// Difficulty bucket derived from the group's average Collins rating.
    var difficulty: VocabDifficulty {
        switch averageCollins {
        case 3.5...: return .core
        case 2.0..<3.5: return .common
        case 1.0..<2.0: return .advanced
        default: return .rare
        }
    }
}

enum VocabDifficulty: String {
    case core = "核心"
    case common = "常用"
    case advanced = "进阶"
    case rare = "生僻"
}

enum VocabLoader {
    /// Words per study group.
    static let groupSize = 50

    /// Loads and decodes the bundled word list, re-ordered by study importance.
    /// The JSON bytes go straight from disk to the decoder — this is cheap (<1MB)
    /// and runs once at store init.
    static func loadBundled() -> [VocabWord] {
        guard let url = Bundle.main.url(forResource: "ielts_words", withExtension: "json") else {
            assertionFailure("ielts_words.json missing from bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let words = try JSONDecoder().decode([VocabWord].self, from: data)
            return words.sorted { $0.importanceKey < $1.importanceKey }
        } catch {
            assertionFailure("failed to decode ielts_words.json: \(error)")
            return []
        }
    }

    /// Slice an importance-ordered word list into fixed-size groups.
    static func makeGroups(from words: [VocabWord]) -> [VocabGroup] {
        stride(from: 0, to: words.count, by: groupSize).enumerated().map { index, start in
            let end = min(start + groupSize, words.count)
            return VocabGroup(id: index, words: Array(words[start..<end]))
        }
    }
}
