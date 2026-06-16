import SwiftUI

/// Review mode: lists every word the user has marked 生 / 半熟, shows each with
/// its annotation style (circle / underline), and starts a review-only session
/// where marks can be changed on the fly.
struct VocabReviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: VocabStore

    private let accent = Color.orange

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color(red: 0.96, green: 0.95, blue: 0.93))
                .ignoresSafeArea()

            let words = store.reviewWords
            if words.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        reviewButton(count: words.count)
                            .padding(.bottom, 4)
                        ForEach(words) { word in
                            row(for: word)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .navigationTitle("复习模式")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reviewButton(count: Int) -> some View {
        NavigationLink {
            StudySessionView(store: store, scope: .review, title: "复习标记词")
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("复习全部 \(count) 个标记词")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accent)
                    .shadow(color: accent.opacity(0.3), radius: 8, y: 4)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func row(for word: VocabWord) -> some View {
        let mark = store.progressByWord[word.word]?.mark ?? .unmarked
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(word.word)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .wordMark(mark)
                if !word.phonetic.isEmpty {
                    Text("/\(word.phonetic)/")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(mark.label)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(mark.color.opacity(0.18)))
                    .foregroundStyle(mark.color)
            }
            if let first = word.senseLines.first {
                Text(first)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : .white)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(accent)
            Text("还没有标记的单词")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("背词时标成「生」或「半熟」的词会进入这里，标成「熟」后移出")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }
}
