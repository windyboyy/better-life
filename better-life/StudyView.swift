import SwiftUI

/// Hands-free interval metronome for studying — e.g. memorizing vocabulary.
/// Fires a short cue every N seconds to prompt switching to the next word.
struct StudyView: View {
    @State private var engine = IntervalCueEngine()
    @State private var store = StoreManager()
    @State private var showPaywall = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    private let presets: [TimeInterval] = [10, 15, 20]

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

    private let accent = Color.indigo

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [backgroundTop, backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                header
                quotaBanner
                intervalSection
                cueToggles
                soundPicker
                Spacer()
                statusDisplay
                startStopButton
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 48)
        }
        .sensoryFeedback(trigger: engine.elapsedTicks) { _, _ in
            engine.vibrationEnabled ? .impact(flexibility: .soft) : nil
        }
        .task {
            engine.isPro = store.isPro
            await store.loadProduct()
        }
        .onChange(of: store.isPro) { _, newValue in
            engine.isPro = newValue
        }
        .onChange(of: engine.reachedFreeLimit) { _, hit in
            if hit {
                showPaywall = true
                engine.clearFreeLimitFlag()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Returning to the foreground: re-align the drifted timers so the next
            // cue is a clean full interval from now instead of a stretched leftover.
            if phase == .active {
                engine.resyncIfRunning()
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(store: store)
        }
        .onDisappear { engine.stop() }
    }

    // MARK: - Free quota banner

    @ViewBuilder
    private var quotaBanner: some View {
        if store.isPro {
            HStack(spacing: 8) {
                Image(systemName: "infinity")
                    .font(.system(size: 14, weight: .bold))
                Text("已解锁 · 无限时长")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(accent)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Capsule().fill(accent.opacity(0.12)))
        } else {
            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 14, weight: .semibold))
                    Text("今日免费剩余 \(timeString(engine.usage.remainingSeconds))")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("解锁无限")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 12)
                        .background(Capsule().fill(accent))
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.gray.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("背单词节拍器")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("每隔几秒提醒你翻到下一个")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Interval picker

    private var intervalSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ForEach(presets, id: \.self) { value in
                    presetButton(value)
                }
            }

            VStack(spacing: 4) {
                HStack {
                    Text("自定义间隔")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("每 \(Int(engine.interval)) 秒")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                }
                Slider(value: $engine.interval, in: 5...60, step: 1)
                    .tint(accent)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colorScheme == .dark ? accent.opacity(0.12) : .white)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
    }

    private func presetButton(_ value: TimeInterval) -> some View {
        let isSelected = Int(engine.interval) == Int(value)
        return Button {
            engine.interval = value
        } label: {
            Text("\(Int(value)) 秒")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? accent : accent.opacity(0.12))
                )
                .foregroundStyle(isSelected ? .white : accent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cue toggles

    private var cueToggles: some View {
        HStack(spacing: 12) {
            cueToggle(title: "震动", icon: "iphone.radiowaves.left.and.right", isOn: $engine.vibrationEnabled)
            cueToggle(title: "铃声", icon: "speaker.wave.2.fill", isOn: $engine.soundEnabled)
        }
    }

    private func cueToggle(title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn.wrappedValue ? accent.opacity(0.15) : Color.gray.opacity(0.1))
            )
            .foregroundStyle(isOn.wrappedValue ? accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sound picker

    private var soundPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("提示音")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(IntervalCueEngine.soundCatalog) { sound in
                        soundChip(sound)
                    }
                }
                .padding(.horizontal, 2)
            }

            if engine.soundEnabled {
                HStack(spacing: 5) {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 11))
                    Text("请关闭手机静音模式，否则听不到提示音")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 4)
    }

    private func soundChip(_ sound: CueSound) -> some View {
        let isSelected = engine.selectedSound == sound
        return Button {
            engine.selectedSound = sound
            engine.preview(sound)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 12))
                Text(sound.name)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(isSelected ? accent : accent.opacity(0.12))
            )
            .foregroundStyle(isSelected ? .white : accent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status

    private var statusDisplay: some View {
        VStack(spacing: 8) {
            Text(timeString(engine.elapsedSeconds))
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(engine.isRunning ? accent : .primary)

            Text("已提醒 \(engine.elapsedTicks) 次")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Start / Stop

    private func handleStartStop() {
        // Stopping is always allowed.
        if engine.isRunning {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) { engine.toggle() }
            return
        }
        // Starting on the free tier requires remaining daily time.
        if !store.isPro {
            engine.usage.refresh()
            guard engine.usage.hasFreeTimeLeft else {
                showPaywall = true
                return
            }
        }
        withAnimation(.spring(duration: 0.3, bounce: 0.2)) { engine.toggle() }
    }

    private var startStopButton: some View {
        Button {
            handleStartStop()
        } label: {
            Text(engine.isRunning ? "停止" : "开始")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(engine.isRunning ? Color.red : accent)
                        .shadow(color: (engine.isRunning ? Color.red : accent).opacity(0.3), radius: 10, y: 5)
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    StudyView()
}
