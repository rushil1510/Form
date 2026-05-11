// Rep.swift
// Form — Data Model: Single Rep
//
// A Rep represents ONE completed repetition within a workout set.
// It captures the quality of that specific rep, not the whole session.
//
// Codable conformance allows Swift to automatically serialize this struct
// to/from JSON using JSONEncoder/JSONDecoder — no manual mapping needed.
// The JSON key names will match the Swift property names by default.

import Foundation

// MARK: - Rep

/// A single completed repetition in a workout session.
///
/// Lifecycle: created by WorkoutView when RepCounter fires repCompleted,
/// populated with the most recent FormAnalyzer output, then appended to Session.reps.
struct Rep: Codable, Identifiable {

    /// Unique identifier. UUID is the standard iOS approach — random 128-bit value,
    /// collision probability is negligible (1 in 2^122).
    let id: UUID

    /// When this rep was completed. Used for time-series charts in SessionDetailView.
    let timestamp: Date

    /// Form quality score for this rep, 0–100.
    ///
    /// Scoring scheme (TODO: implement in FormAnalyzer):
    ///   100: Perfect form — no deviations detected
    ///   70–99: Minor warnings — fixable, low injury risk
    ///   40–69: Significant issues — should address before increasing weight
    ///   0–39: Dangerous form — stop and correct immediately
    let formScore: Int

    /// The most impactful error detected during this rep, if any.
    /// Stored as a string so it displays directly in SessionDetailView.
    /// nil means the rep was rated "good" with no specific fault.
    let dominantError: String?

    // MARK: - Convenience Initializer

    init(
        id: UUID = UUID(),          // Default to a new UUID so callers don't have to specify
        timestamp: Date = Date(),   // Default to now
        formScore: Int,
        dominantError: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.formScore = formScore
        self.dominantError = dominantError
    }
}
