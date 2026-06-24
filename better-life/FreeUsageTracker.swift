import Foundation
import Observation

/// Tracks how many seconds of metronome time the user has consumed on the free
/// tier today.
///
/// The allowance renews each calendar day, but within a day it **accumulates** —
/// it is keyed to the date and persisted to the Keychain on every recorded
/// second, so none of these refund used time:
/// - stopping and starting a new session (the counter is not per-session),
/// - relaunching the app,
/// - force-quitting the app mid-session,
/// - deleting and reinstalling the app (Keychain survives reinstalls).
@Observable
final class FreeUsageTracker {
    /// Daily free allowance, in seconds (10 minutes).
    static let dailyLimitSeconds = 10 * 60

    private static let dateKey = "freeUsageDate"
    private static let secondsKey = "freeUsageSeconds"

    /// Seconds consumed on the day identified by `currentDate`.
    private(set) var secondsUsedToday = 0

    /// The day (yyyy-MM-dd) the current count belongs to.
    private var currentDate: String

    init() {
        currentDate = Keychain.string(for: Self.dateKey) ?? DateHelper.todayString()
        secondsUsedToday = Int(Keychain.string(for: Self.secondsKey) ?? "") ?? 0
        rolloverIfNeeded()
    }

    /// Seconds of free metronome time left today.
    var remainingSeconds: Int {
        max(0, Self.dailyLimitSeconds - secondsUsedToday)
    }

    /// Whether the user still has free time left today.
    var hasFreeTimeLeft: Bool {
        remainingSeconds > 0
    }

    /// Records one elapsed second of free usage and persists it immediately.
    /// Call once per second while the metronome runs on the free tier.
    func recordOneSecond() {
        rolloverIfNeeded()
        secondsUsedToday += 1
        persist()
    }

    /// Re-checks the calendar day so the UI reflects a daily renewal even if the
    /// app has been sitting open across midnight. Safe to call before reading the
    /// remaining allowance (e.g. when the user taps start).
    func refresh() {
        rolloverIfNeeded()
    }

    /// Resets the counter when the calendar day changes (daily renewal).
    private func rolloverIfNeeded() {
        let today = DateHelper.todayString()
        guard today != currentDate else { return }
        currentDate = today
        secondsUsedToday = 0
        persist()
    }

    private func persist() {
        Keychain.set(currentDate, for: Self.dateKey)
        Keychain.set(String(secondsUsedToday), for: Self.secondsKey)
    }
}
