import SwiftUI
import SwiftData
import Combine

/// "摘叶飞花"自动复习模式：逐词过所有标记为 生/半熟 的词，
/// 生词给 10 秒，半熟词给 5 秒，倒计时归零自动切到下一个。
/// 复用 IntervalCueEngine 的提示音和震动设置。
struct FlyingPetalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    let store: VocabStore

    // MARK: - Session state

    @State private var queue: [VocabWord] = []
    @State private var currentIndex = 0
    @State private var secondsLeft = 10
    @State private var totalSeconds = 10
    @State private var isRevealed = false
    @State private var isPaused = false
    @State private var isDone = false
    @State private var reviewedThisSession = 0

    // MARK: - Breathing Light (asymmetric automotive-style glow)
    private let breathCycleDuration: TimeInterval = 5.0  // one full inhale→exhale cycle ~5s

    // Cue triggers
    @State private var cueTick = 0          // bumped on each auto-advance → haptic
    @State private var speech = SpeechPlayer()
    @State private var cueEngine = IntervalCueEngine()

    // Timer — fires every second when active & not paused
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Computed

    private var accent: Color { Color(red: 130/255, green: 200/255, blue: 228/255) }  // #82C8E4 Gemini sky blue

    private var backgroundTop: Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.14, blue: 0.18)
            : Color(red: 0.94, green: 0.97, blue: 0.99)
    }

    private var backgroundBottom: Color {
        colorScheme == .dark
            ? Color(red: 0.06, green: 0.09, blue: 0.13)
            : Color.white
    }

    private var currentWord: VocabWord? {
        guard currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    private var currentMark: WordMark {
        guard let word = currentWord else { return .unmarked }
        return store.progressByWord[word.word]?.mark ?? .unmarked
    }

    private var timerColor: Color {
        switch currentMark {
        case .raw: return .red
        case .half: return .orange
        default: return accent
        }
    }

    // Auto-reveal thresholds
    private var autoRevealAt: Int {
        currentMark == .raw ? 3 : 2
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

            if queue.isEmpty || isDone {
                doneState
            } else if let word = currentWord {
                VStack(spacing: 0) {
                    headerBar
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    cardSection(word: word)
                        .id(currentIndex)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                        .padding(.horizontal, 20)

                    bottomControls(word: word)
                        .padding(.top, 20)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("摘叶飞花")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { buildSession() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !isPaused { /* timer auto-resumes via publisher */ }
        }
        .onReceive(timer) { _ in
            guard !isPaused, !isDone, currentWord != nil else { return }
            if secondsLeft > 0 {
                secondsLeft -= 1
                // 提前 2 秒响铃 + 震动，预告即将切词
                if secondsLeft == 2 {
                    cueTick += 1
                    if cueEngine.soundEnabled {
                        cueEngine.preview(cueEngine.selectedSound)
                    }
                }
                // Auto-reveal definition in the final seconds
                if !isRevealed && secondsLeft <= autoRevealAt {
                    withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                        isRevealed = true
                    }
                }
            }
            if secondsLeft <= 0 {
                advanceToNext()
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: cueTick)
    }

    // MARK: - Session lifecycle

    private func buildSession() {
        queue = store.reviewWords
        currentIndex = 0
        reviewedThisSession = 0
        isDone = queue.isEmpty
        isPaused = false
        setupForCurrentWord()
    }

    private func setupForCurrentWord() {
        guard let word = currentWord else { return }
        let mark = store.progressByWord[word.word]?.mark ?? .raw
        switch mark {
        case .raw:
            totalSeconds = 10
        case .half:
            totalSeconds = 5
        default:
            totalSeconds = 10
        }
        secondsLeft = totalSeconds
        isRevealed = false
    }

    // MARK: - Advance / Skip

    private func advanceToNext() {
        goToNextWord()
    }

    private func skipToNext() {
        goToNextWord()
    }

    private func goToNextWord() {
        reviewedThisSession += 1
        if currentIndex + 1 < queue.count {
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                currentIndex += 1
            }
            setupForCurrentWord()
        } else {
            withAnimation(.easeInOut(duration: 0.4)) {
                isDone = true
            }
        }
    }

    // MARK: - Marking

    private func markWord(_ newMark: WordMark) {
        guard let word = currentWord else { return }
        let today = DateHelper.todayString()

        if let progress = store.progressByWord[word.word] {
            progress.setMark(newMark, today: today)
        } else {
            let progress = WordProgress(word: word.word, dueDate: today)
            modelContext.insert(progress)
            progress.setMark(newMark, today: today)
        }
        try? modelContext.save()

        // If retired, skip to next immediately
        if newMark == .familiar {
            withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                skipToNext()
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            // Progress text
            HStack(spacing: 6) {
                Image(systemName: "leaf")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                Text("第 \(currentIndex + 1) / \(queue.count) 个")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Sound toggle
            Button {
                cueEngine.soundEnabled.toggle()
            } label: {
                Image(systemName: cueEngine.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(cueEngine.soundEnabled ? accent : .secondary)
            }
            .buttonStyle(.plain)

            // Vibration toggle
            Button {
                cueEngine.vibrationEnabled.toggle()
            } label: {
                Image(systemName: cueEngine.vibrationEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    .font(.system(size: 16))
                    .foregroundStyle(cueEngine.vibrationEnabled ? accent : .secondary)
                    .padding(.leading, 12)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Card section

    // MARK: - Breathing Curve (asymmetric automotive-style)

    private func breathPhase(at date: Date) -> Double {
        let t = date.timeIntervalSince1970
            .truncatingRemainder(dividingBy: breathCycleDuration) / breathCycleDuration
        return breathCurve(t)
    }

    /// Raw breathing curve from 0…1 fraction:
    /// dim pause → slow inhale → bright pause → faster exhale → dim pause
    private func breathCurve(_ t: Double) -> Double {
        let dimPause1   = 0.08
        let inhale      = 0.50
        let brightPause = 0.10

        if t < dimPause1 { return 0 }
        if t < dimPause1 + inhale {
            let p = (t - dimPause1) / inhale
            return easeInOutCubic(p)
        }
        if t < dimPause1 + inhale + brightPause { return 1 }
        if t < 0.92 {
            let exhaleLen = 0.92 - dimPause1 - inhale - brightPause
            let p = (t - dimPause1 - inhale - brightPause) / exhaleLen
            return 1 - easeOutCubic(p)
        }
        return 0
    }

    private func easeInOutCubic(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private func easeOutCubic(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    private func cardSection(word: VocabWord) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Word + speaker
                HStack(spacing: 16) {
                    Text(word.word)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.4)
                        .wordMark(currentMark)

                    Button {
                        speech.speak(word.word)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(1) // 喇叭按钮不被压缩
                }

                if !word.phonetic.isEmpty {
                    Text("/\(word.phonetic)/")
                        .font(.system(size: 20, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                // Definition reveal
                if isRevealed {
                    Divider().padding(.horizontal, 32).padding(.vertical, 8)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(word.senseLines, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 19, design: .rounded))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Text("回想一下释义…")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                }
            }
            .padding(.vertical, 40)
            .padding(.horizontal, 28)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            TimelineView(.animation) { timeline in
                let nearEnd = secondsLeft <= 2

                // Two-colour alternating breathing — each colour gets one full breath cycle
                let totalCycle = breathCycleDuration * 2
                let t = timeline.date.timeIntervalSince1970
                    .truncatingRemainder(dividingBy: totalCycle)

                let isFirstColor = t < breathCycleDuration
                let fraction = isFirstColor
                    ? t / breathCycleDuration
                    : (t - breathCycleDuration) / breathCycleDuration
                let phase = breathCurve(fraction)

                // Gemini saturated palette — dark: blue→amber  /  light: green→blue
                let activePair = colorScheme == .dark
                    ? (Color(red: 80/255,  green: 195/255, blue: 255/255),   // vivid sky blue
                       Color(red: 255/255, green: 200/255, blue: 20/255))    // rich amber gold
                    : (Color(red: 70/255,  green: 220/255, blue: 140/255),   // saturated mint green
                       Color(red: 80/255,  green: 195/255, blue: 255/255))   // vivid sky blue
                let activeColor = isFirstColor ? activePair.0 : activePair.1

                // Amplitude — boosted for visible saturation
                let glowMax:  Double = nearEnd ? 0.26 : 0.16
                let blurMax:  Double = nearEnd ? 22 : 14
                let innerMax: Double = nearEnd ? 0.14 : 0.09

                ZStack {
                    // ① Base card surface — tinted by active colour, no pure white
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : activeColor.opacity(0.06))

                    // ② Soft outer glow
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(activeColor)
                        .opacity(phase * glowMax * 0.75)
                        .blur(radius: phase * blurMax + 8)
                        .scaleEffect(1 + phase * 0.016)

                    // ③ Inner luminous core — radial gradient
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    activeColor.opacity(phase * innerMax),
                                    activeColor.opacity(phase * innerMax * 0.55),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 30,
                                endRadius: 200
                            )
                        )

                    // ④ Edge highlight
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(activeColor.opacity(phase * glowMax * 0.35), lineWidth: 1.5)
                        .blur(radius: 1.5)
                }
                .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRevealed {
                withAnimation(.spring(duration: 0.3, bounce: 0.1)) { isRevealed = true }
            }
        }
    }

    // MARK: - Bottom controls

    private func bottomControls(word: VocabWord) -> some View {
        VStack(spacing: 16) {
            // Mark row (visible when revealed)
            if isRevealed {
                HStack(spacing: 12) {
                    markButton(.raw, icon: "circle", label: "生")
                    markButton(.half, icon: "minus", label: "半熟")
                    markButton(.familiar, icon: "checkmark", label: "熟")
                }
            }

            // Action row
            HStack(spacing: 12) {
                // Pause / Resume
                Button {
                    isPaused.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        Text(isPaused ? "继续" : "暂停")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(isPaused ? accent : Color.gray.opacity(0.15))
                    )
                    .foregroundStyle(isPaused ? .white : .primary)
                }
                .buttonStyle(.plain)

                // Skip
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                        skipToNext()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                        Text("跳过")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(timerColor.opacity(0.15))
                    )
                    .foregroundStyle(timerColor)
                }
                .buttonStyle(.plain)
            }

            // Reveal button (hidden when already revealed)
            if !isRevealed {
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.1)) { isRevealed = true }
                } label: {
                    Text("显示释义")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
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
    }

    private func markButton(_ mark: WordMark, icon: String, label: String) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                markWord(mark)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(mark.color)
                    .shadow(color: mark.color.opacity(0.3), radius: 8, y: 4)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Done state

    private var doneState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(accent)
                .symbolEffect(.bounce, options: .repeating)

            Text("飞花已尽，叶落归根")
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(.primary)

            Text("本次共复习 \(reviewedThisSession) 个单词")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            // Show updated counts
            let raw = store.progressByWord.values.filter { $0.mark == .raw }.count
            let half = store.progressByWord.values.filter { $0.mark == .half }.count
            if raw + half > 0 {
                HStack(spacing: 16) {
                    Label("生 \(raw)", systemImage: "circle")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.red)
                    Label("半熟 \(half)", systemImage: "minus")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                }
                .padding(.top, 4)
            } else {
                Text("所有标记词都已清空 🎉")
                    .font(.system(size: 15))
                    .foregroundStyle(accent)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.4)) {
                    buildSession()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("再来一轮")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 36)
                .background(Capsule().fill(accent.opacity(0.15)))
                .foregroundStyle(accent)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 40)
        .onAppear {
            // Refresh progress in case marks changed
            // store.progressByWord is refreshed when we save
        }
    }
}

#Preview {
    FlyingPetalsView(store: VocabStore(modelContext: ModelContext(try! ModelContainer(for: WordProgress.self))))
}
