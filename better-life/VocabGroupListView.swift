import SwiftUI

/// Lists the importance-ordered study groups with per-group progress, and pushes
/// a scoped study session when one is tapped.
struct VocabGroupListView: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: VocabStore

    private let accent = VocabView.accent

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(store.groups) { group in
                    NavigationLink {
                        StudySessionView(store: store, scope: .group(group.id), title: group.displayName)
                    } label: {
                        row(for: group)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(
            (colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color(red: 0.96, green: 0.95, blue: 0.93))
                .ignoresSafeArea()
        )
        .navigationTitle("按分组学习")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for group: VocabGroup) -> some View {
        let stats = store.stats(for: group)
        return HStack(spacing: 14) {
            ProgressRing(fraction: stats.fraction, tint: accent)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(group.displayName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    difficultyBadge(group.difficulty)
                }
                Text("已学会 \(stats.learned) · 已学 \(stats.started) / \(stats.total)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : .white)
                .shadow(color: .black.opacity(0.04), radius: 5, y: 2)
        )
    }

    private func difficultyBadge(_ difficulty: VocabDifficulty) -> some View {
        let color = difficultyColor(difficulty)
        return Text(difficulty.rawValue)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private func difficultyColor(_ difficulty: VocabDifficulty) -> Color {
        switch difficulty {
        case .core: return .red
        case .common: return .orange
        case .advanced: return .teal
        case .rare: return .gray
        }
    }
}

/// A thin circular progress ring used in the group list.
struct ProgressRing: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
    }
}
