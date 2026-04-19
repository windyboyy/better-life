import SwiftUI
import SwiftData
import Combine

struct TodayView: View {
    var store: HabitStore
    @State private var currentTime = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter.string(from: currentTime)
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: currentTime)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: currentTime)
        switch hour {
        case 5..<12: return "早上好"
        case 12..<14: return "中午好"
        case 14..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "夜深了"
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundTop: Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.15, blue: 0.17)
            : Color(red: 0.96, green: 0.95, blue: 0.93)
    }

    private var backgroundBottom: Color {
        colorScheme == .dark
            ? Color(red: 0.1, green: 0.1, blue: 0.1)
            : Color.white
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [backgroundTop, backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Habit cards — centered on full screen height
            VStack(spacing: 20) {
                HabitCard(
                    icon: "figure.run",
                    title: "锻炼 30 分钟",
                    subtitle: "动起来，保持活力",
                    isDone: store.todayRecord?.exerciseDone ?? false,
                    activeColor: Color.green,
                    inactiveColor: Color.green.opacity(0.12),
                    action: { store.toggleExercise() }
                )

                HabitCard(
                    icon: "book.fill",
                    title: "读书 30 分钟",
                    subtitle: "充实自己，开阔视野",
                    isDone: store.todayRecord?.readingDone ?? false,
                    activeColor: Color.teal,
                    inactiveColor: Color.teal.opacity(0.12),
                    action: { store.toggleReading() }
                )
            }
            .padding(.horizontal, 20)

            // Date & time header — pinned to top
            VStack {
                VStack(spacing: 6) {
                    Text(greetingText)
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text(dateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(timeText)
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                .padding(.top, 48)

                Spacer()

                MottoView(
                    exerciseDone: store.todayRecord?.exerciseDone ?? false,
                    readingDone: store.todayRecord?.readingDone ?? false
                )
                .padding(.bottom, 32)
            }
        }
        .onReceive(timer) { time in
            currentTime = time
        }
    }
}

private struct HabitCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isDone: Bool
    let activeColor: Color
    let inactiveColor: Color
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var cardBackground: Color {
        if isDone { return activeColor }
        return colorScheme == .dark
            ? activeColor.opacity(0.2)
            : inactiveColor
    }

    private var iconCircleColor: Color {
        if isDone { return .white.opacity(0.25) }
        return colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color.white
    }

    var body: some View {
        Button(action: {
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                action()
            }
        }) {
            HStack(spacing: 16) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(iconCircleColor)
                        .frame(width: 52, height: 52)
                        .shadow(color: isDone ? .clear : .black.opacity(0.06), radius: 4, y: 2)

                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(isDone ? .white : activeColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))

                    Text(isDone ? "已完成" : subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(isDone ? .white.opacity(0.8) : .secondary)
                }

                Spacer()

                // Checkmark
                ZStack {
                    Circle()
                        .strokeBorder(isDone ? Color.white.opacity(0.5) : activeColor.opacity(0.4), lineWidth: 2.5)
                        .frame(width: 36, height: 36)

                    if isDone {
                        Circle()
                            .fill(.white.opacity(0.3))
                            .frame(width: 36, height: 36)

                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardBackground)
                    .shadow(
                        color: isDone ? activeColor.opacity(0.3) : .black.opacity(0.06),
                        radius: isDone ? 10 : 4,
                        y: isDone ? 5 : 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isDone ? Color.clear : activeColor.opacity(0.3),
                        lineWidth: 1.5
                    )
            )
            .foregroundStyle(isDone ? .white : .primary)
        }
        .buttonStyle(HabitButtonStyle())
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isDone)
    }
}

private struct HabitButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

private struct MottoView: View {
    let exerciseDone: Bool
    let readingDone: Bool

    private var allDone: Bool { exerciseDone && readingDone }

    var body: some View {
        let prefix = "回报率最高的自我投资："
        let exercisePart = "每天 30 分钟运动"
        let separator = " + "
        let readingPart = "30 分钟阅读"

        let dimColor = Color.gray.opacity(0.3)

        let prefixColor: Color = allDone ? .green : dimColor
        let exerciseColor: Color = exerciseDone ? .green : dimColor
        let separatorColor: Color = allDone ? .green : dimColor
        let readingColor: Color = readingDone ? .green : dimColor

        (Text(prefix).foregroundColor(prefixColor)
        + Text(exercisePart).foregroundColor(exerciseColor)
        + Text(separator).foregroundColor(separatorColor)
        + Text(readingPart).foregroundColor(readingColor))
            .font(.system(size: 13, weight: .regular, design: .rounded))
            .multilineTextAlignment(.center)
            .animation(.easeInOut(duration: 0.3), value: exerciseDone)
            .animation(.easeInOut(duration: 0.3), value: readingDone)
    }
}

#Preview {
    let container = try! ModelContainer(for: DailyRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    TodayView(store: HabitStore(modelContext: container.mainContext))
}
