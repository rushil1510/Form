// AppState.swift
// Form — Global Application State
//
// This file defines AppState: the single source of truth for app-wide state.
//
// WHY ObservableObject?
// SwiftUI's data flow model is unidirectional: state flows DOWN from parent to
// child views, and events flow UP via bindings or callbacks. ObservableObject
// + @EnvironmentObject is SwiftUI's built-in solution for state that many
// distant views need to read or modify — without threading it manually through
// every intermediate view.
//
// When a @Published property changes, SwiftUI automatically re-renders any
// view that declared @EnvironmentObject var appState: AppState. This is the
// reactive programming model — views "subscribe" to state.
//
// ARCHITECTURE NOTE:
// AppState intentionally holds only COORDINATION state (what exercise is active,
// is a session running). Heavy domain logic lives in feature-specific managers
// (CameraManager, PoseDetector, etc.). This keeps AppState lean and avoids
// turning it into a "god object."

import Foundation
import Combine // Combine is Apple's reactive framework — ObservableObject uses it under the hood

// MARK: - AppState

/// AppState is the global coordinator for the Form app.
/// It's injected at the root (FormApp.swift) and observed throughout the UI.
///
/// Think of it like Redux store in React — one authoritative state tree,
/// though much simpler since we don't need reducers for this app's complexity level.
final class AppState: ObservableObject {

    // MARK: - Published Properties

    // @Published is a property wrapper from Combine.
    // Every time this value changes, it fires an objectWillChange notification,
    // which tells SwiftUI to re-render any observing view.

    /// The exercise type currently selected by the user.
    /// nil means no exercise is selected yet (shown on the workout setup screen).
    @Published var selectedExercise: ExerciseType? = nil

    /// True when a recording/analysis session is actively running.
    /// Used to show/hide the live camera UI and disable navigation tabs.
    @Published var isSessionActive: Bool = false

    /// The current live session being built as reps are detected.
    /// This is nil between sessions and populated once the user starts recording.
    @Published var currentSession: Session? = nil

    /// Live rep count shown in the workout HUD (heads-up display).
    /// Driven by RepCounter's publisher — see RepCounter.swift.
    @Published var liveRepCount: Int = 0

    /// The most recent form feedback from the analyzer.
    /// Updated every frame (or every N frames for performance — TBD in FormAnalyzer).
    @Published var latestFeedback: FormFeedback = .good

    // MARK: - Session Lifecycle

    /// Begins a new workout session for the given exercise type.
    /// Call this when the user taps "Start" in WorkoutView.
    func startSession(for exercise: ExerciseType) {
        // Create a fresh Session object — reps will be appended as they complete
        currentSession = Session(
            id: UUID(),
            date: Date(),
            exerciseType: exercise,
            reps: [],
            notes: nil
        )
        selectedExercise = exercise
        isSessionActive = true
        liveRepCount = 0
        latestFeedback = .good

        print("[AppState] Session started for \(exercise.rawValue)")
    }

    /// Ends the active session, returning the completed Session for persistence.
    /// Call this when the user taps "Stop" in WorkoutView.
    /// - Returns: The completed Session, or nil if none was active.
    @discardableResult
    func endSession() -> Session? {
        guard let session = currentSession else { return nil }
        isSessionActive = false
        currentSession = nil
        liveRepCount = 0

        print("[AppState] Session ended. Reps completed: \(session.reps.count)")
        return session
    }

    /// Appends a completed rep to the current session and increments the live counter.
    /// Called by RepCounter (via WorkoutView) when a rep is detected.
    func recordRep(_ rep: Rep) {
        currentSession?.reps.append(rep)
        liveRepCount += 1
    }
}
