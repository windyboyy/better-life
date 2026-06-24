import Foundation
import Observation
import AudioToolbox
import AVFoundation
import MediaPlayer
import UIKit

/// Drives a hands-free kettlebell-style interval workout: an optional prepare
/// countdown, then `sets` repetitions of `work` seconds of exercise followed by
/// `rest` seconds of recovery. During the prepare and rest phases the last few
/// seconds are counted down — both a per-second tick and a spoken English number
/// ("3", "2", "1") — so the user knows, eyes-free, when the next set begins.
///
/// Modeled on `IntervalCueEngine`: it keeps the screen awake while running, draws
/// down the shared free-tier daily allowance, and re-aligns its timer when the
/// app returns to the foreground. Haptics are driven by the view layer via
/// `.sensoryFeedback` observing `feedbackTick`.
@Observable
final class WorkoutTimerEngine {

    /// Language used for the spoken countdown and phase announcements.
    enum VoiceLanguage: String, CaseIterable, Identifiable {
        case chinese
        case english

        var id: String { rawValue }

        /// Display name shown in the settings picker.
        var label: String {
            switch self {
            case .chinese: return "中文"
            case .english: return "英文"
            }
        }

        /// BCP-47 locale for `AVSpeechSynthesisVoice`.
        var speechLocale: String {
            switch self {
            case .chinese: return "zh-CN"
            case .english: return "en-US"
            }
        }

        /// Spoken when a work set begins.
        var goPhrase: String {
            switch self {
            case .chinese: return "开始"
            case .english: return "Go"
            }
        }

        /// Spoken when a rest period begins.
        var restPhrase: String {
            switch self {
            case .chinese: return "开始休息"
            case .english: return "Rest"
            }
        }

        /// Spoken when the whole workout finishes.
        func finishPhrase(sets: Int) -> String {
            switch self {
            case .chinese: return "训练结束，已完成 \(sets) 组"
            case .english: return "Workout complete. \(sets) sets done"
            }
        }
    }

    /// The stage of the workout the engine is currently in.
    enum Phase: Equatable {
        /// Not started, or fully reset.
        case idle
        /// Pre-workout countdown before the first set.
        case prepare
        /// Active exercise within a set.
        case work
        /// Recovery between sets.
        case rest
        /// All sets complete.
        case finished

        /// Short label shown on the big status card.
        var title: String {
            switch self {
            case .idle: return "准备开始"
            case .prepare: return "准备"
            case .work: return "运动"
            case .rest: return "休息"
            case .finished: return "完成"
            }
        }
    }

    // MARK: - Configurable parameters

    /// Seconds of exercise per set.
    var workSeconds = 30
    /// Seconds of recovery between sets.
    var restSeconds = 15
    /// Number of sets to perform.
    var sets = 5
    /// Optional countdown before the first set (0 disables it).
    var prepareSeconds = 5
    /// How many seconds before a prepare/rest phase ends to start counting down
    /// (tick + spoken number).
    var countdownLeadSeconds = 3

    // MARK: - Cue toggles

    /// Whether phase changes and countdown ticks play a sound.
    var soundEnabled = true
    /// Whether the rest/prepare countdown is spoken aloud ("3", "2", "1").
    var voiceEnabled = true

    /// Language for the spoken countdown and phase announcements. Persisted.
    var voiceLanguage: VoiceLanguage = .english {
        didSet {
            UserDefaults.standard.set(voiceLanguage.rawValue, forKey: Self.voiceLanguageKey)
        }
    }

    private static let voiceLanguageKey = "workoutVoiceLanguage"
    /// Whether each cue triggers a vibration (handled in the view layer).
    var vibrationEnabled = true

    /// When true, the user's Apple Music / local library playback (via the system
    /// Music app) is auto-played during work and auto-paused during rest. Only
    /// affects the built-in Music app — iOS doesn't allow controlling third-party
    /// players like NetEase or QQ Music. Toggling it re-syncs immediately.
    var appleMusicEnabled = false {
        didSet { syncMusic() }
    }

    // MARK: - Observed state

    /// Whether the timer is actively counting (false while paused or finished).
    private(set) var isRunning = false
    /// Current workout stage.
    private(set) var phase: Phase = .idle
    /// Seconds remaining in the current phase.
    private(set) var phaseRemaining = 0
    /// The set currently in progress, 1-based. 0 before the first set begins.
    private(set) var currentSet = 0
    /// Increments on every audible cue so the view can fire haptics via
    /// `.sensoryFeedback(trigger:)`.
    private(set) var feedbackTick = 0

    // MARK: - Free-tier plumbing (shared with the metronome)

    /// Tracks the free-tier daily time allowance (persisted, cross-session).
    let usage = FreeUsageTracker()

    /// Whether the user has unlocked unlimited time. Set by the view from
    /// `StoreManager`. When true, usage is never counted or limited.
    var isPro = false

    /// Set true when a running free session is auto-stopped because the daily
    /// allowance ran out. The view observes this to present the paywall, then
    /// resets it via `clearFreeLimitFlag()`.
    private(set) var reachedFreeLimit = false

    // MARK: - Internals

    private var timer: Timer?
    private let synthesizer = AVSpeechSynthesizer()

    /// Receives `AVSpeechSynthesizer` finish/cancel callbacks so we can lift audio
    /// ducking — restoring other apps' (e.g. NetEase / QQ Music) volume — once a
    /// spoken cue ends, rather than keeping it ducked for the whole workout.
    @ObservationIgnored private let speechCoordinator = SpeechCoordinator()

    /// Pending debounced un-duck (see `scheduleDuckRestore()`).
    @ObservationIgnored private var pendingDuckRestore: DispatchWorkItem?

    /// Serial queue for all `AVAudioSession` activate/deactivate calls. Those are
    /// synchronous and can block — iOS warns that running them on the main thread
    /// causes UI unresponsiveness, and it's what made the countdown timer stall
    /// and skip a number at phase changes. A *serial* queue keeps activate/
    /// deactivate strictly ordered so the session never ends up in the wrong state.
    @ObservationIgnored private let audioSessionQueue =
        DispatchQueue(label: "com.betterlife.workout.audioSession")

    /// How long to wait after a spoken cue finishes before restoring other apps'
    /// volume. Must exceed the ~1s gap between consecutive countdown numbers so
    /// the whole "3, 2, 1, Go" sequence stays a single ducking episode.
    private let duckRestoreDelay: TimeInterval = 1.3

    /// Monotonic timestamp of the last *accepted* tick, used to drop bunched
    /// ticks (see `tick()`).
    @ObservationIgnored private var lastTickUptime: Double?

    /// Minimum spacing between accepted ticks. A repeating `Timer` whose run loop
    /// stalled (e.g. while audio starts at a phase change) can fire twice in quick
    /// succession to catch up; anything closer than this is a catch-up artefact,
    /// not a real second, and is dropped so the on-screen number never skips.
    private let minTickInterval: TimeInterval = 0.5

    /// Controls the system Music app's playback queue, so changes persist with
    /// whatever the user already queued in the Music app.
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer

    /// Cache of registered SystemSoundIDs, keyed by file name.
    @ObservationIgnored private var registeredIDs: [String: SystemSoundID] = [:]

    /// System sound files (under `/System/Library/Audio/UISounds`) used for each
    /// kind of cue. Chosen to be audibly distinct from one another.
    private enum Cue: String {
        case workStart = "begin_record"   // entering a work set — "go"
        case restStart = "Tock"           // entering rest — softer, lower
        case tick = "Tink"                // per-second countdown tick
        case finish = "sms-received1"     // workout complete — three-tone
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.voiceLanguageKey),
           let lang = VoiceLanguage(rawValue: saved) {
            voiceLanguage = lang
        }
        configureAudioSession()
        speechCoordinator.onSpeechFinished = { [weak self] in
            self?.scheduleDuckRestore()
        }
        synthesizer.delegate = speechCoordinator
        preloadCues()
    }

    /// Registers every cue's `SystemSoundID` up front. The first use of a sound
    /// otherwise loads its file from disk synchronously, which can briefly stall
    /// the run loop mid-countdown — doing it at init keeps phase changes smooth.
    private func preloadCues() {
        for cue in [Cue.workStart, .restStart, .tick, .finish] {
            _ = systemSoundID(for: cue)
        }
    }

    /// Configures the shared audio session for background playback so that the
    /// timer, cues and spoken countdown keep running while the screen is locked
    /// or the app is in the background.
    ///
    /// `.playback` + `.spokenAudio` is the recommended combo for speech-heavy
    /// workout timers: it tells iOS this is a long-form audio session (not a
    /// transient sound effect), which keeps `RunLoop` timers alive and lets
    /// `AVSpeechSynthesizer` continue speaking after the user locks the screen.
    ///
    /// `.duckOthers` briefly lowers other apps' volume while we cue, then
    /// restores it — so background music is attenuated rather than stopped.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        )
    }

    /// Activates the shared audio session off the main thread (see
    /// `audioSessionQueue`). Re-applies `.duckOthers` whenever we start speaking.
    private func activateSessionAsync() {
        audioSessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }

    /// Deactivates the shared audio session off the main thread, notifying other
    /// apps so their volume (the ducked music) is restored.
    private func deactivateSessionAsync() {
        audioSessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation
            )
        }
    }

    /// Releases the audio session so the system can reclaim resources when the
    /// workout is fully stopped (reset or finished). We intentionally do NOT
    /// deactivate on pause — the session stays alive so the user can resume
    /// quickly, including from the locked screen.
    private func deactivateAudioSession() {
        cancelDuckRestore()
        deactivateSessionAsync()
    }

    /// Schedules lifting of the `.duckOthers` attenuation a short moment after a
    /// spoken cue finishes. Ducking persists for as long as our session is active,
    /// so the only way to restore other apps' volume is to deactivate the session
    /// (with `.notifyOthersOnDeactivation`).
    ///
    /// We debounce rather than restore immediately: the countdown speaks "3", "2",
    /// "1" (then "Go") as separate utterances ~1s apart, and restoring between
    /// each would make background music dip-and-pop three times in a row. By
    /// waiting `duckRestoreDelay` — longer than the gap between consecutive
    /// numbers — and cancelling the pending restore whenever the next number
    /// starts (`cancelDuckRestore()` in `speak()`), the whole countdown becomes a
    /// single ducking episode: music dips once when it begins and rises once after
    /// it ends. Driven by `SpeechCoordinator` when the synthesizer goes idle.
    private func scheduleDuckRestore() {
        pendingDuckRestore?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingDuckRestore = nil
            self?.deactivateSessionAsync()
        }
        pendingDuckRestore = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duckRestoreDelay, execute: work)
    }

    /// Cancels a pending un-duck so an imminent spoken number keeps the current
    /// ducking episode alive instead of letting it bounce.
    private func cancelDuckRestore() {
        pendingDuckRestore?.cancel()
        pendingDuckRestore = nil
    }

    // MARK: - Derived UI helpers

    /// Total number of seconds in the current phase, for progress display.
    var phaseTotal: Int {
        switch phase {
        case .prepare: return prepareSeconds
        case .work: return workSeconds
        case .rest: return restSeconds
        case .idle, .finished: return 0
        }
    }

    /// Whether there is a session in progress that can be paused/resumed (as
    /// opposed to a fresh idle or finished state).
    var isActiveSession: Bool {
        phase == .work || phase == .rest || phase == .prepare
    }

    // MARK: - Controls

    /// Begins a fresh workout from the first phase, or resumes a paused one.
    func start() {
        guard !isRunning else { return }
        reachedFreeLimit = false
        usage.refresh()

        if !isActiveSession {
            // Fresh start: jump to the first meaningful phase.
            currentSet = 0
            feedbackTick = 0
            if prepareSeconds > 0 {
                enter(.prepare)
            } else {
                beginNextSet()
            }
        }

        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
        preWarmSynthesizer()
        scheduleTimer()
        syncMusic()
    }

    /// Pauses the workout, preserving the current phase, remaining time and set.
    func pause() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        syncMusic()
    }

    /// Stops and clears the workout back to the idle state.
    func reset() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        synthesizer.stopSpeaking(at: .immediate)
        phase = .idle
        phaseRemaining = 0
        currentSet = 0
        UIApplication.shared.isIdleTimerDisabled = false
        deactivateAudioSession()
        syncMusic()
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    /// Clears the auto-stop flag after the view has reacted to it.
    func clearFreeLimitFlag() {
        reachedFreeLimit = false
    }

    /// Re-aligns the running timer to the current moment. Call this when the app
    /// returns to the foreground: while suspended the timer is frozen and its
    /// next fire date drifts, so without this the next tick lands late. We don't
    /// compensate for elapsed background time — we just restart the 1s cadence
    /// cleanly from now, preserving the phase and remaining counters.
    func resyncIfRunning() {
        guard isRunning else { return }
        timer?.invalidate()
        scheduleTimer()
    }

    // MARK: - Timer loop

    private func scheduleTimer() {
        // Fresh cadence: the next tick should be a full second away, so forget the
        // previous tick's timestamp (don't let the bunching guard drop it).
        lastTickUptime = nil
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        // Drop catch-up ticks: if the run loop stalled (e.g. while audio spins up
        // at a phase change) the repeating timer can fire twice almost at once to
        // realign. Ignoring the bunched second keeps the visible countdown from
        // skipping a number (e.g. "14" flashing past in a blink at rest start).
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastTickUptime, now - last < minTickInterval { return }
        lastTickUptime = now

        // Draw down the free allowance first; auto-stop if it runs out.
        if !isPro {
            usage.recordOneSecond()
            if !usage.hasFreeTimeLeft {
                pause()
                reachedFreeLimit = true
                return
            }
        }

        phaseRemaining -= 1

        if phaseRemaining > 0 {
            // Tick every second through prepare/rest, and speak the number over
            // the last `countdownLeadSeconds` seconds.
            if phase == .rest || phase == .prepare {
                countdownTick(phaseRemaining)
            }
            return
        }

        // Current phase just ended — advance the state machine.
        advance()
    }

    private func advance() {
        switch phase {
        case .prepare:
            beginNextSet()
        case .work:
            if currentSet < sets {
                enter(.rest)
            } else {
                finish()
            }
        case .rest:
            beginNextSet()
        case .idle, .finished:
            break
        }
    }

    /// Starts the next set's work phase, incrementing the set counter.
    private func beginNextSet() {
        currentSet += 1
        enter(.work)
    }

    /// Enters `phase`, resetting its remaining time and firing its entry cue.
    private func enter(_ newPhase: Phase) {
        phase = newPhase
        switch newPhase {
        case .prepare:
            phaseRemaining = prepareSeconds
        case .work:
            phaseRemaining = workSeconds
            playCue(.workStart)
            if voiceEnabled { speak(voiceLanguage.goPhrase) }
        case .rest:
            phaseRemaining = restSeconds
            playCue(.restStart)
            if voiceEnabled { speak(voiceLanguage.restPhrase) }
        case .idle, .finished:
            phaseRemaining = 0
        }
        syncMusic()
    }

    private func finish() {
        phase = .finished
        phaseRemaining = 0
        isRunning = false
        timer?.invalidate()
        timer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        playCue(.finish)
        if voiceEnabled {
            // Speak the closing phrase, then let `SpeechCoordinator` release the
            // session once it finishes — deactivating now would cut the phrase off
            // and leave other audio ducked.
            speak(voiceLanguage.finishPhrase(sets: sets))
        } else {
            deactivateAudioSession()
        }
        syncMusic()
    }

    // MARK: - Music control

    /// Plays the system music player for the whole running workout (work *and*
    /// rest) and pauses it only when the session stops — paused, reset or
    /// finished. No-op unless the user has enabled Apple Music control.
    private func syncMusic() {
        guard appleMusicEnabled else { return }
        if isRunning {
            musicPlayer.play()
        } else {
            musicPlayer.pause()
        }
    }

    // MARK: - Cues

    /// Per-second cue during prepare/rest: a tick every second, plus the spoken
    /// number ("3", "2", "1") over the final `countdownLeadSeconds` seconds.
    private func countdownTick(_ remaining: Int) {
        if soundEnabled {
            AudioServicesPlaySystemSound(systemSoundID(for: .tick))
        }
        if voiceEnabled && remaining <= countdownLeadSeconds {
            speak(String(remaining))
        }
        feedbackTick += 1
    }

    private func playCue(_ cue: Cue) {
        if soundEnabled {
            AudioServicesPlaySystemSound(systemSoundID(for: cue))
        }
        feedbackTick += 1
    }

    /// Pre-warms `AVSpeechSynthesizer` so the first real countdown number ("3")
    /// isn't delayed while the engine initialises. Spoken at max rate and zero
    /// volume — the user never hears it, but it primes the audio session + voice.
    private func preWarmSynthesizer() {
        guard voiceEnabled else { return }
        cancelDuckRestore()
        activateSessionAsync()
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: " ")
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage.speechLocale)
        utterance.volume = 0.0
        utterance.rate = AVSpeechUtteranceMaximumSpeechRate
        synthesizer.speak(utterance)
    }

    private func speak(_ text: String) {
        cancelDuckRestore()
        activateSessionAsync()
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage.speechLocale)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    /// Lazily registers a system sound file and caches its SystemSoundID.
    private func systemSoundID(for cue: Cue) -> SystemSoundID {
        if let id = registeredIDs[cue.rawValue] { return id }
        var id: SystemSoundID = 0
        let url = URL(fileURLWithPath: "/System/Library/Audio/UISounds/\(cue.rawValue).caf")
        AudioServicesCreateSystemSoundID(url as CFURL, &id)
        registeredIDs[cue.rawValue] = id
        return id
    }

    deinit {
        timer?.invalidate()
        for id in registeredIDs.values {
            AudioServicesDisposeSystemSoundID(id)
        }
    }
}

/// Bridges `AVSpeechSynthesizer`'s delegate callbacks back to the engine. It fires
/// `onSpeechFinished` only when the synthesizer has fully stopped (no further
/// queued utterances), so the engine can lift audio ducking exactly once per
/// spoken cue rather than on every utterance boundary.
private final class SpeechCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    var onSpeechFinished: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        notifyIfIdle(synthesizer)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        notifyIfIdle(synthesizer)
    }

    /// `isSpeaking` can still report the just-finished utterance synchronously
    /// inside the callback, and a new `speak()` may be about to enqueue another
    /// utterance. Re-checking on the next main-queue turn settles both races, so
    /// we only un-duck when speech has genuinely stopped.
    private func notifyIfIdle(_ synthesizer: AVSpeechSynthesizer) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !synthesizer.isSpeaking else { return }
            self.onSpeechFinished?()
        }
    }
}
