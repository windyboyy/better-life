import SwiftUI
import UIKit
import MediaPlayer

/// Hands-free kettlebell interval timer. The main screen is a distraction-free
/// countdown (phase, seconds remaining, set progress); all configuration lives
/// in a settings sheet behind the "运动设置" glass button.
struct WorkoutTimerView: View {
    @State private var engine = WorkoutTimerEngine()
    @State private var store = StoreManager()
    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var musicDenied = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    /// Vibrant "vitality" green — reads as movement/health, and stays distinct
    /// from the red pause button and the blue rest phase.
    private let accent = Color(red: 0.13, green: 0.70, blue: 0.42)

    private var backgroundTop: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.14, blue: 0.12)
            : Color.white
    }

    private var backgroundBottom: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.08, blue: 0.08)
            : Color.white
    }

    /// Color of the big status display, by phase.
    private var phaseColor: Color {
        switch engine.phase {
        case .work: return accent
        case .rest, .prepare: return .blue
        case .idle, .finished: return .secondary
        }
    }

    /// Rounded-card background shared by the settings cards — a soft accent tint
    /// on the white page, so the cards read as a matching color family.
    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(accent.opacity(colorScheme == .dark ? 0.14 : 0.08))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [backgroundTop, backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                statusDisplay
                Spacer()
                controlButtons
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .sensoryFeedback(trigger: engine.feedbackTick) { _, _ in
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
            if phase == .active {
                engine.resyncIfRunning()
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(store: store)
        }
        .onDisappear { engine.pause() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                Text("壶铃计时器")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Label("运动设置", systemImage: "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.glass)
                .tint(accent)
            }
            quotaBanner
        }
    }

    /// Full-width quota line below the title, mirroring the study metronome's
    /// banner so the two timers feel like one app.
    @ViewBuilder
    private var quotaBanner: some View {
        if store.isPro {
            HStack(spacing: 8) {
                Image(systemName: "infinity")
                    .font(.system(size: 14, weight: .bold))
                Text("已解锁 · 无限时长")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
            }
            .foregroundStyle(accent)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(0.12))
            )
        } else {
            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 14, weight: .semibold))
                    Text("今日剩余 \(timeString(engine.usage.remainingSeconds))")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
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

    // MARK: - Center status

    private var statusDisplay: some View {
        VStack(spacing: 10) {
            Text(engine.phase.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(phaseColor)

            Text("\(displayedRemaining)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(phaseColor)
                .contentTransition(.numericText())
                .animation(.snappy, value: displayedRemaining)

            Text(setLabel)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    /// The big number to show: live remaining seconds while running, or the
    /// configured work length when idle.
    private var displayedRemaining: Int {
        switch engine.phase {
        case .idle: return engine.workSeconds
        case .finished: return 0
        default: return engine.phaseRemaining
        }
    }

    private var setLabel: String {
        switch engine.phase {
        case .idle: return "共 \(engine.sets) 组"
        case .finished: return "全部完成 · \(engine.sets) 组"
        default: return "第 \(engine.currentSet) / \(engine.sets) 组"
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Controls

    private var controlButtons: some View {
        HStack(spacing: 14) {
            if engine.isActiveSession {
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) { engine.reset() }
                } label: {
                    Text("重置")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.gray.opacity(0.2))
                        )
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }

            Button {
                handleStartPause()
            } label: {
                Text(primaryButtonTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(engine.isRunning ? Color.red : accent)
                            .shadow(color: (engine.isRunning ? Color.red : accent).opacity(0.3), radius: 10, y: 5)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private var primaryButtonTitle: String {
        if engine.isRunning { return "暂停" }
        if engine.phase == .finished { return "再来一组" }
        return engine.isActiveSession ? "继续" : "开始"
    }

    private func handleStartPause() {
        if engine.isRunning {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) { engine.pause() }
            return
        }
        if engine.phase == .finished {
            engine.reset()
        }
        if !store.isPro {
            engine.usage.refresh()
            guard engine.usage.hasFreeTimeLeft else {
                showPaywall = true
                return
            }
        }
        withAnimation(.spring(duration: 0.3, bounce: 0.2)) { engine.start() }
    }

    // MARK: - Settings sheet

    private var settingsSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [backgroundTop, backgroundBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        workoutParamsCard
                        cueCard
                        musicCard
                    }
                    .padding(20)
                }
            }
            .navigationTitle("运动设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showSettings = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Workout parameters card

    private var workoutParamsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardTitle("运动设置", icon: "dumbbell.fill")

            stepperRow(title: "运动", value: $engine.workSeconds, range: 5...300, step: 5, unit: "秒")
            stepperRow(title: "休息", value: $engine.restSeconds, range: 5...300, step: 5, unit: "秒")
            stepperRow(title: "组数", value: $engine.sets, range: 1...50, step: 1, unit: "组")
            stepperRow(title: "准备", value: $engine.prepareSeconds, range: 0...30, step: 1, unit: "秒")
            stepperRow(title: "读秒提前", value: $engine.countdownLeadSeconds, range: 0...10, step: 1, unit: "秒")

            if engine.isActiveSession {
                Text("有进行中的训练，结束或重置后才能修改。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(cardBackground)
        .disabled(engine.isActiveSession)
        .opacity(engine.isActiveSession ? 0.5 : 1)
    }

    private func stepperRow(title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, unit: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
            Spacer()
            Text("\(value.wrappedValue) \(unit)")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
                .monospacedDigit()
                .frame(minWidth: 56, alignment: .trailing)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
        }
    }

    // MARK: - Cue card

    private var cueCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardTitle("提醒方式", icon: "bell.fill")

            cueToggle(title: "震动", icon: "iphone.radiowaves.left.and.right", isOn: $engine.vibrationEnabled)
            cueToggle(title: "铃声", icon: "speaker.wave.2.fill", isOn: $engine.soundEnabled)
            cueToggle(title: "语音读秒", icon: "waveform", isOn: $engine.voiceEnabled)

            Text("语音语言")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            HStack(spacing: 10) {
                ForEach(WorkoutTimerEngine.VoiceLanguage.allCases) { lang in
                    languageChip(lang)
                }
            }

            if engine.soundEnabled || engine.voiceEnabled {
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
        .padding(20)
        .background(cardBackground)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn.wrappedValue ? accent.opacity(0.15) : Color.gray.opacity(0.1))
            )
            .foregroundStyle(isOn.wrappedValue ? accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func languageChip(_ lang: WorkoutTimerEngine.VoiceLanguage) -> some View {
        let isSelected = engine.voiceLanguage == lang
        return Button {
            engine.voiceLanguage = lang
        } label: {
            Text(lang.label)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? accent : accent.opacity(0.12))
                )
                .foregroundStyle(isSelected ? .white : accent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Music card

    private var musicCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("运动配乐", icon: "music.note")

            appleMusicToggle

            Text("或打开你常用的音乐 App 放上歌，提示音会叠在音乐上、全程不停：")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                ForEach(musicApps) { app in
                    Button {
                        launch(app)
                    } label: {
                        Text(app.name)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(app.color.opacity(0.15)))
                            .foregroundStyle(app.color)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("网易云 / QQ 音乐 iOS 不支持自动控制，只有 Apple Music 能自动播放/停止。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(20)
        .background(cardBackground)
    }

    /// Toggle for auto-playing the system Music app for the whole workout.
    private var appleMusicToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if engine.appleMusicEnabled {
                    engine.appleMusicEnabled = false
                } else {
                    requestAppleMusicControl()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Apple Music 自动控制")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("开始训练时自动播放，整套结束后停止")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: engine.appleMusicEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(engine.appleMusicEnabled ? Color.pink.opacity(0.15) : Color.gray.opacity(0.1))
                )
                .foregroundStyle(engine.appleMusicEnabled ? Color.pink : .secondary)
            }
            .buttonStyle(.plain)

            if musicDenied {
                Text("未获得音乐访问权限，请在「设置 → Better Life」中开启，或先在「音乐」App 的「已下载」里添加歌曲。")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cardTitle(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(.system(size: 17, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Music shortcuts

    /// A music app the user can launch to play their own soundtrack, which our
    /// cues mix over (we never control or pause third-party players — iOS doesn't
    /// allow that).
    private struct MusicApp: Identifiable {
        let name: String
        let scheme: String
        let appStoreID: String
        let color: Color
        var id: String { scheme }
    }

    private let musicApps: [MusicApp] = [
        MusicApp(name: "网易云音乐", scheme: "orpheus://", appStoreID: "590338362", color: .red),
        MusicApp(name: "QQ音乐", scheme: "qqmusic://", appStoreID: "414603431", color: .green),
        MusicApp(name: "Apple Music", scheme: "music://", appStoreID: "1108187390", color: .pink),
    ]

    /// Opens a music app by URL scheme; if it isn't installed, falls back to its
    /// App Store page.
    private func launch(_ app: MusicApp) {
        guard let url = URL(string: app.scheme) else { return }
        UIApplication.shared.open(url, options: [:]) { success in
            guard !success,
                  let store = URL(string: "https://apps.apple.com/app/id\(app.appStoreID)")
            else { return }
            UIApplication.shared.open(store)
        }
    }

    private func requestAppleMusicControl() {
        MPMediaLibrary.requestAuthorization { status in
            Task { @MainActor in
                let granted = (status == .authorized)
                engine.appleMusicEnabled = granted
                musicDenied = !granted
            }
        }
    }
}

#Preview {
    WorkoutTimerView()
}
