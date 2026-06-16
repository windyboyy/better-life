import SwiftUI
import SwiftData

/// 背单词 tab home: overall progress, a finish-time estimate, and entry points
/// into the three study modes (smart review, study-by-group, 错题本).
struct VocabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: VocabStore?

    static let accent = Color.indigo

    private var backgroundTop: Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.15, blue: 0.17)
            : Color(red: 0.96, green: 0.95, blue: 0.93)
    }

    private var backgroundBottom: Color {
        colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color.white
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                if let store {
                    ScrollView {
                        VStack(spacing: 18) {
                            header(store)
                            estimateCard(store)
                            modeButtons(store)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 40)
                        .padding(.bottom, 32)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if store == nil { store = VocabStore(modelContext: modelContext) }
            else { store?.refreshIfDateChanged() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store?.refreshIfDateChanged() }
        }
    }

    // MARK: - Header

    private func header(_ store: VocabStore) -> some View {
        VStack(spacing: 10) {
            Text("背单词")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("雅思核心词 · \(store.totalWords) 词 · \(store.groups.count) 组")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let learnedFrac = store.totalWords == 0 ? 0 : Double(store.learnedCount) / Double(store.totalWords)
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.15))
                        Capsule().fill(Self.accent)
                            .frame(width: geo.size.width * CGFloat(learnedFrac))
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("已学会 \(store.learnedCount)")
                    Spacer()
                    Text("已开始 \(store.startedCount) / \(store.totalWords)")
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Finish estimate

    private func estimateCard(_ store: VocabStore) -> some View {
        let days = store.daysToFinish(perDay: store.newPerDay)
        let date = store.finishDate(perDay: store.newPerDay)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                Text("学完预估")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
            }

            Stepper(value: Binding(
                get: { store.newPerDay },
                set: { store.newPerDay = max(5, min(200, $0)) }
            ), in: 5...200, step: 5) {
                Text("每天新词 \(store.newPerDay) 个")
                    .font(.system(size: 15))
            }

            if store.remainingCount == 0 {
                Text("全部 \(store.totalWords) 词都已开始学习 🎉")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                Text("还剩 \(store.remainingCount) 个新词，约 \(days) 天过完一遍")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                if let date {
                    Text("预计 \(Self.dateString(date)) 学完")
                        .font(.system(size: 13))
                        .foregroundStyle(Self.accent)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colorScheme == .dark ? Self.accent.opacity(0.12) : .white)
                .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        )
    }

    // MARK: - Mode buttons

    private func modeButtons(_ store: VocabStore) -> some View {
        VStack(spacing: 12) {
            NavigationLink {
                StudySessionView(store: store, scope: .smart, title: "智能复习")
            } label: {
                modeRow(icon: "brain.head.profile", title: "智能复习",
                        subtitle: "到期复习 + 每天新词", tint: Self.accent)
            }

            NavigationLink {
                VocabGroupListView(store: store)
            } label: {
                modeRow(icon: "square.grid.2x2", title: "按分组学习",
                        subtitle: "\(store.groups.count) 组 · 每组 \(VocabLoader.groupSize) 词", tint: .teal)
            }

            NavigationLink {
                VocabReviewView(store: store)
            } label: {
                modeRow(icon: "pencil.and.list.clipboard", title: "复习模式",
                        subtitle: store.reviewCount == 0 ? "暂无标记词" : "生 \(store.rawCount) · 半熟 \(store.halfCount)", tint: .orange)
            }
        }
    }

    private func modeRow(icon: String, title: String, subtitle: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : .white)
                .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        )
    }

    static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }
}

#Preview {
    VocabView()
        .modelContainer(for: WordProgress.self, inMemory: true)
}
