// RepCounter.swift
// Form — Rep Detection via Joint Angle Peak Analysis
//
// ─── HOW REP DETECTION WORKS ──────────────────────────────────────────────────
// A rep is a CYCLE in a joint angle time series:
//
//   Squat (hip angle): Standing ~160° → Bottom ~70° → Standing ~160°
//   Deadlift (hip angle): Standing ~170° → Floor ~70° → Standing ~170°
//   Bench Press (elbow angle): Extended ~170° → Chest ~70° → Extended ~170°
//
// We use a 3-state FSM: IDLE → DESCENDING → ASCENDING → (rep!) → IDLE
//
// ─── ALGORITHM DESIGN ─────────────────────────────────────────────────────────
// LOW_THRESHOLD (~90°): entering DESCENDING state when angle drops below this
// HIGH_THRESHOLD (~150°): entering ASCENDING state when angle rises above this
//
// A simple moving average over the last N frames smooths Vision's per-frame jitter.
//
// ─── WHY NOT ML FOR REP COUNTING? ────────────────────────────────────────────
// Simple angle thresholding is reliable, interpretable, and needs no training data.
// ML would add complexity without meaningful accuracy gains for this use case.

import Foundation
import Combine
import Vision

// MARK: - Rep Counter

/// Tracks a joint angle time series and fires a publisher when a rep completes.
final class RepCounter: ObservableObject {

    // MARK: - Published State

    @Published private(set) var repCount: Int = 0

    // MARK: - Publishers

    /// Fires whenever a complete rep is detected.
    let repCompleted = PassthroughSubject<Void, Never>()

    // MARK: - Configuration

    private let lowThreshold: Double
    private let highThreshold: Double

    // MARK: - Internal State

    private enum RepPhase {
        case idle        // Standing / between reps
        case descending  // Angle decreasing (going down into the rep)
        case ascending   // Angle increasing (coming back up)
    }

    private var phase: RepPhase = .idle
    private var angleHistory: [Double] = []
    private let smoothingWindowSize: Int = 5

    // MARK: - Initializer

    init(lowThreshold: Double = 95.0, highThreshold: Double = 150.0) {
        self.lowThreshold = lowThreshold
        self.highThreshold = highThreshold
    }

    // MARK: - Public Interface

    /// Process a new joint map and update rep state.
    /// - Parameters:
    ///   - joints: Current frame joint positions from PoseDetector.
    ///   - exercise: Determines which joint angle to track.
    func update(joints: JointMap, exercise: ExerciseType) {
        let (jointA, jointB, jointC) = exercise.repDetectionJoint

        guard let a = joints[jointA], let b = joints[jointB], let c = joints[jointC] else { return }

        let rawAngle = GeometryHelpers.angle(a: a, b: b, c: c)
        let smoothedAngle = smooth(newAngle: rawAngle)
        updateStateMachine(angle: smoothedAngle)
    }

    /// Resets the counter for a new set or session.
    func reset() {
        repCount = 0
        phase = .idle
        angleHistory.removeAll()
    }

    // MARK: - Private: Smoother

    /// Sliding window moving average to reduce Vision jitter.
    private func smooth(newAngle: Double) -> Double {
        angleHistory.append(newAngle)
        if angleHistory.count > smoothingWindowSize { angleHistory.removeFirst() }
        return angleHistory.reduce(0, +) / Double(angleHistory.count)
    }

    // MARK: - Private: State Machine

    private func updateStateMachine(angle: Double) {
        switch phase {
        case .idle:
            if angle < lowThreshold { phase = .descending }

        case .descending:
            if angle > highThreshold { phase = .ascending }

        case .ascending:
            if angle < lowThreshold { phase = .descending; return }
            repCount += 1
            phase = .idle
            repCompleted.send()
            print("[RepCounter] ✅ Rep #\(repCount) — angle: \(String(format: "%.1f", angle))°")
        }
    }
}
