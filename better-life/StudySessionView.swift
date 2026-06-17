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
    @State private var dragOffset: CGFloat = 0
    @State private var undoTrigger = 0   // bumped on each undo to fire haptic feedback

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
        .sensoryFeedback(.impact(weight: .light), trigger: undoTrigger)
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
        .offset(x: dragOffset)
        .overlay(alignment: .leading) {
            // Visual hint that fades in proportionally as the user swipes right.
            HStack(spacing: 4) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                Text("撤销")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.ultraThinMaterial))
            .padding(.leading, 4)
            .opacity(store.canUndo ? min(Double(dragOffset) / 60, 1) : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !store.isRevealed {
                withAnimation(.spring(duration: 0.3, bounce: 0.1)) { store.reveal() }
            }
        }
        .simultaneousGesture(undoDrag)
    }

    /// Right-swipe gesture: with damping (~0.6×), triggers undo when the card is
    /// dragged past ~80 pt. Only active when `canUndo` is true, and only for a
    /// predominantly horizontal swipe so vertical motion can't trip it.
    private var undoDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                if store.canUndo,
                   value.translation.width > 0,
                   abs(value.translation.width) > abs(value.translation.height) {
                    dragOffset = value.translation.width * 0.6
                }
            }
            .onEnded { value in
                if store.canUndo,
                   value.translation.width > 80,
                   abs(value.translation.width) > abs(value.translation.height) {
                    undoTrigger += 1
                    withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                        store.undoLastMark()
                    }
                }
                withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                    dragOffset = 0
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

            if store.canUndo {
                Button {
                    undoTrigger += 1
                    withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                        store.undoLastMark()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("撤销上一个标记")
                    }
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(Capsule().stroke(accent.opacity(0.3)))
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }

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
