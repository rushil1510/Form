// Session.swift
// Form — Data Model: Workout Session
//
// A Session is the top-level container for a workout: it groups all reps in
// a single set/exercise attempt and links them to a date and exercise type.
//
// Hierarchy: Session → [Rep] → formScore (per rep)
// This mirrors how a fitness tracker like Strava structures its events.

import Foundation

// MARK: - Session

/// A complete workout session — one exercise, one or more reps, one timeframe.
///
/// Sessions are the primary unit of persistence. SessionStore saves [Session] to disk.
/// Each session is independent: you can delete, filter, or display them individually.
struct Session: Codable, Identifiable {

    let id: UUID

    /// When the session started (set when the user taps "Start" in WorkoutView).
    let date: Date

    /// Which exercise was performed. Determines which analyzer and rep counter rules apply.
    let exerciseType: ExerciseType

    /// All completed reps in this session, in chronological order.
    /// Appended by AppState.recordRep() during the session.
    var reps: [Rep]

    /// Optional free-text notes the user can add after a session (future feature).
    /// Kept as String? (optional) so it doesn't waste space when not provided.
    var notes: String?

    // MARK: - Computed Properties

    /// Returns the aggregate form score for this session, or nil if no reps.
    var formScore: FormScore? {
        FormScore.compute(from: reps, exercise: exerciseType)
    }

    /// The session's duration can't be tracked with just a start date in this model.
    /// TODO: Add an endDate property in a future model version.
    /// For now, display date as "formatted start time."
    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
