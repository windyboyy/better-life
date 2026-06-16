import SwiftUI

/// The flashcard study screen, shared by all study modes. It builds its queue
/// from the given `scope` on appear, then drives the tap-to-reveal → mark loop
/// via `VocabStore`. Marking (生 / 半熟 / 熟) is the only grading; 熟 retires a
/// word from the review pool.
struct StudySessionView: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: VocabStore
    let scope: SessionScope
    let title: String

    @State private var speech = SpeechPlayer()

    private let accent = VocabView.accent

    var body: some View {
        VStack(spacing: 20) {
            progressBar

            if let word = store.currentWord {
                card(word: word)
                Spacer()
                controls(word: word)
            } else {
                Spacer()
                doneState
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.startSession(scope) }
    }

    // MARK: - Progress

    private var progressBar: some View {
        let total = max(store.plannedCount, 1)
        let done = min(store.reviewedThisSession, total)
        return VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.15))
                    Capsule().fill(accent)
                        .frame(width: geo.size.width * CGFloat(done) / CGFloat(total))
                }
            }
            .frame(height: 8)
            Text("本次进度 \(done)/\(store.plannedCount)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Card

    private func card(word: VocabWord) -> some View {
        let mark = store.mark(for: word)
        return VStack(spacing: 16) {
            Spacer()

            HStack(spacing: 12) {
                Text(word.word)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .wordMark(mark)

                Button {
                    speech.speak(word.word)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }

            if !word.phonetic.isEmpty {
                Text("/\(word.phonetic)/")
                    .font(.system(size: 18, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if store.isRevealed {
                Divider().padding(.horizontal, 40).padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(word.senseLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 17, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Text("点击卡片查看释义")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(colorScheme == .dark ? accent.opacity(0.12) : .white)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !store.isRevealed {
                withAnimation(.spring(duration: 0.3, bounce: 0.1)) { store.reveal() }
            }
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private func controls(word: VocabWord) -> some View {
        if store.isRevealed {
            HStack(spacing: 12) {
                markButton(.raw, systemImage: "circle")
                markButton(.half, systemImage: "minus")
                markButton(.familiar, systemImage: "checkmark")
            }
        } else {
            Button {
                withAnimation(.spring(duration: 0.3, bounce: 0.1)) { store.reveal() }
            } label: {
                Text("显示释义")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(accent)
                            .shadow(color: accent.opacity(0.3), radius: 10, y: 5)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private func markButton(_ mark: WordMark, systemImage: String) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.1)) { store.mark(mark) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                Text(mark.label)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(mark.color)
                    .shadow(color: mark.color.opacity(0.3), radius: 8, y: 4)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Done

    private var doneState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(accent)
            Text(doneTitle)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("本次共学习 \(store.reviewedThisSession) 个单词")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Button {
                withAnimation { store.startSession(scope) }
            } label: {
                Text("再来一组")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .padding(.vertical, 14)
                    .padding(.horizontal, 32)
                    .background(Capsule().fill(accent.opacity(0.15)))
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private var doneTitle: String {
        switch scope {
        case .review: return "标记词都过完啦！"
        default: return store.reviewedThisSession == 0 ? "暂时没有要学的词" : "本组完成！"
        }
    }
}
