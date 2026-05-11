// FormScore.swift
// Form — Data Model: Aggregate Session Score
//
// FormScore is a SUMMARY of a completed session — computed after all reps are done.
// It's separate from Rep (per-rep data) to follow the Single Responsibility Principle:
//   Rep = raw data, FormScore = derived analytics
//
// This is analogous to a "statistics" row in a database vs the raw event rows.

import Foundation

// MARK: - FormScore

/// Aggregated form quality metrics for a completed workout session.
///
/// Computed by SessionStore after a session ends. Not stored independently —
/// it's a computed view over Session.reps that can be regenerated at any time.
///
/// WHY store it separately instead of computing on the fly in the UI?
/// For sessions with hundreds of reps, recomputing in SwiftUI's body could
/// cause performance issues. Pre-computing and caching as FormScore is cleaner.
struct FormScore: Codable, Identifiable {

    let id: UUID
    let exerciseType: ExerciseType
    let averageScore: Double  // Mean of all Rep.formScore values, 0–100
    let repCount: Int
    let date: Date

    // MARK: - Computed Properties (not stored in JSON)

    /// Letter grade representation. Cosmetic — shown in SessionDetailView header.
    var grade: String {
        switch averageScore {
        case 90...100: return "A"
        case 80..<90:  return "B"
        case 70..<80:  return "C"
        case 60..<70:  return "D"
        default:       return "F"
        }
    }

    // MARK: - Factory

    /// Creates a FormScore by aggregating an array of reps.
    /// - Parameters:
    ///   - reps: All reps in the session.
    ///   - exercise: The exercise type for this session.
    /// - Returns: A new FormScore, or nil if reps is empty (avoid division by zero).
    static func compute(from reps: [Rep], exercise: ExerciseType) -> FormScore? {
        guard !reps.isEmpty else { return nil }
        let average = Double(reps.map(\.formScore).reduce(0, +)) / Double(reps.count)
        return FormScore(
            id: UUID(),
            exerciseType: exercise,
            averageScore: average,
            repCount: reps.count,
            date: Date()
        )
    }
}
