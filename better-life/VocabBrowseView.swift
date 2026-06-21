import SwiftUI

/// Browse the word library by difficulty tier. Each tier shows progress and
/// pushes into a scoped study session for that difficulty.
struct VocabBrowseView: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: VocabStore

    private let accent = VocabView.accent

    /// Tiers to show (excluding 生僻 unless there are words).
    private var tiers: [VocabDifficulty] {
        let all: [VocabDifficulty] = [.core, .common, .advanced, .rare]
        return all.filter { store.statsForDifficulty($0).total > 0 }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(tiers, id: \.self) { tier in
                    NavigationLink {
                        StudySessionView(
                            store: store,
                            scope: .difficulty(tier),
                            title: "\(tier.rawValue)词"
                        )
                    } label: {
                        row(for: tier)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(
            (colorScheme == .dark
             ? Color(red: 0.1, green: 0.1, blue: 0.1)
             : Color(red: 0.95, green: 0.96, blue: 0.98))
            .ignoresSafeArea()
        )
        .navigationTitle("浏览词库")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Tier row

    private func row(for tier: VocabDifficulty) -> some View {
        let stats = store.statsForDifficulty(tier)
        return HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(tierColor(tier).opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: tierIcon(tier))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tierColor(tier))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(tier.rawValue)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(tierDescription(tier))
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(tierColor(tier).opacity(0.15)))
                        .foregroundStyle(tierColor(tier))
                }
                // Progress line
                HStack(spacing: 6) {
                    Text("\(stats.learned) / \(stats.total) 已掌握")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    if stats.total > 0 {
                        Text("· \(Int((stats.fraction * 100).rounded()))%")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(tierColor(tier))
                    }
                }
            }

            Spacer()

            // Mini progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.18), lineWidth: 4)
                    .frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: max(0.01, min(1, stats.fraction)))
                    .stroke(tierColor(tier), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 36, height: 36)
            }

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

    // MARK: - Helpers

    private func tierColor(_ tier: VocabDifficulty) -> Color {
        switch tier {
        case .core: return .red
        case .common: return .orange
        case .advanced: return .teal
        case .rare: return .gray
        }
    }

    private func tierIcon(_ tier: VocabDifficulty) -> String {
        switch tier {
        case .core: return "flame.fill"
        case .common: return "star.fill"
        case .advanced: return "sparkles"
        case .rare: return "leaf.fill"
        }
    }

    private func tierDescription(_ tier: VocabDifficulty) -> String {
        switch tier {
        case .core: return "高频必备"
        case .common: return "日常常用"
        case .advanced: return "低频高阶"
        case .rare: return "极少出现"
        }
    }
}
