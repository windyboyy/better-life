import Foundation
import Observation
import AudioToolbox
import UIKit

/// A selectable cue tone backed by a built-in iOS system sound file under
/// `/System/Library/Audio/UISounds`. Using the file path (rather than a numeric
/// SystemSoundID) keeps the display name and the actual sound in sync and works
/// identically on the simulator and a device.
struct CueSound: Identifiable, Hashable {
    /// File name without extension, e.g. "Tink".
    let fileName: String
    /// Display name shown in the picker.
    let name: String

    var id: String { fileName }

    var fileURL: URL {
        URL(fileURLWithPath: "/System/Library/Audio/UISounds/\(fileName).caf")
    }
}

/// Drives a hands-free interval metronome: every `interval` seconds it fires a
/// single short cue (sound and/or haptic) to prompt the user to move on — e.g.
/// switch to the next vocabulary word while memorizing.
///
/// Designed for the foreground, screen-on use case: while running it keeps the
/// screen awake so the cues never stop. Haptic feedback is driven by the view
/// layer via `.sensoryFeedback` observing `elapsedTicks`; sound is played here.
@Observable
final class IntervalCueEngine {
    /// Built-in cue tones the user can choose from.
    static let soundCatalog: [CueSound] = [
        CueSound(fileName: "Tink", name: "叮"),
        CueSound(fileName: "Tock", name: "嗒"),
        CueSound(fileName: "key_press_click", name: "咔哒"),
        CueSound(fileName: "sms-received1", name: "三连音"),
        CueSound(fileName: "new-mail", name: "提示"),
        CueSound(fileName: "begin_record", name: "短音"),
    ]

    /// Whether the metronome is currently running.
    private(set) var isRunning = false
    /// Number of cues fired in the current session.
    private(set) var elapsedTicks = 0
    /// Seconds elapsed since the current session started.
    private(set) var elapsedSeconds = 0

    /// Tracks the free-tier daily time allowance (persisted, cross-session).
    let usage = FreeUsageTracker()

    /// Whether the user has unlocked unlimited time. Set by the view from
    /// `StoreManager`. When true, usage is never counted or limited.
    var isPro = false

    /// Set true when a running free session is auto-stopped because the daily
    /// allowance ran out. The view observes this to present the paywall, then
    /// resets it via `clearFreeLimitFlag()`.
    private(set) var reachedFreeLimit = false

    /// Interval between cues, in seconds. Changing it mid-session restarts the
    /// cue timer with the new pace (without resetting elapsed counters).
    var interval: TimeInterval = 15 {
        didSet {
            guard isRunning, interval != oldValue else { return }
            restartCueTimer()
        }
    }

    /// Whether each cue plays a sound.
    var soundEnabled = true
    /// Whether each cue triggers a vibration (handled in the view layer).
    var vibrationEnabled = true

    /// The cue tone played on each tick. Persisted across launches.
    var selectedSound: CueSound {
        didSet {
            UserDefaults.standard.set(selectedSound.fileName, forKey: Self.soundKey)
        }
    }

    private static let soundKey = "cueSoundFileName"

    private var cueTimer: Timer?
    private var secondTimer: Timer?

    /// Cache of registered SystemSoundIDs, keyed by file name. Not observed —
    /// it's an internal playback cache, not UI state.
    @ObservationIgnored private var registeredIDs: [String: SystemSoundID] = [:]

    init() {
        let savedName = UserDefaults.standard.string(forKey: Self.soundKey)
        selectedSound = Self.soundCatalog.first { $0.fileName == savedName } ?? Self.soundCatalog[0]
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        elapsedTicks = 0
        elapsedSeconds = 0
        reachedFreeLimit = false
        usage.refresh()
        UIApplication.shared.isIdleTimerDisabled = true
        scheduleCueTimer()
        scheduleSecondTimer()
    }

    /// Clears the auto-stop flag after the view has reacted to it.
    func clearFreeLimitFlag() {
        reachedFreeLimit = false
    }

    /// Re-aligns the running timers to the current moment. Call this when the app
    /// returns to the foreground: while suspended in the background the timers are
    /// frozen and their next fire dates drift, so without this the first cue after
    /// resuming lands at an irregular interval (e.g. 18s instead of 10s). We don't
    /// try to compensate for background time — we just restart the cadence cleanly
    /// from now, preserving the elapsed counters.
    func resyncIfRunning() {
        guard isRunning else { return }
        cueTimer?.invalidate()
        secondTimer?.invalidate()
        scheduleCueTimer()
        scheduleSecondTimer()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        cueTimer?.invalidate()
        cueTimer = nil
        secondTimer?.invalidate()
        secondTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    /// Plays a sound immediately so the user can audition it from the picker.
    func preview(_ sound: CueSound) {
        AudioServicesPlaySystemSound(systemSoundID(for: sound))
    }

    private func scheduleCueTimer() {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.fire()
        }
        RunLoop.main.add(timer, forMode: .common)
        cueTimer = timer
    }

    private func scheduleSecondTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickSecond()
        }
        RunLoop.main.add(timer, forMode: .common)
        secondTimer = timer
    }

    /// One-second tick: advances the session clock and, on the free tier, draws
    /// down the persisted daily allowance — auto-stopping when it runs out.
    private func tickSecond() {
        elapsedSeconds += 1
        guard !isPro else { return }
        usage.recordOneSecond()
        if !usage.hasFreeTimeLeft {
            stop()
            reachedFreeLimit = true
        }
    }

    private func restartCueTimer() {
        cueTimer?.invalidate()
        scheduleCueTimer()
    }

    private func fire() {
        elapsedTicks += 1
        if soundEnabled {
            AudioServicesPlaySystemSound(systemSoundID(for: selectedSound))
        }
        // Vibration is driven by the view via `.sensoryFeedback(trigger: elapsedTicks)`.
    }

    /// Lazily registers a system sound file and caches its SystemSoundID.
    private func systemSoundID(for sound: CueSound) -> SystemSoundID {
        if let id = registeredIDs[sound.fileName] { return id }
        var id: SystemSoundID = 0
        AudioServicesCreateSystemSoundID(sound.fileURL as CFURL, &id)
        registeredIDs[sound.fileName] = id
        return id
    }

    deinit {
        cueTimer?.invalidate()
        secondTimer?.invalidate()
        for id in registeredIDs.values {
            AudioServicesDisposeSystemSoundID(id)
        }
    }
}
