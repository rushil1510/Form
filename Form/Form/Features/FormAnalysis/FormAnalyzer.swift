// FormAnalyzer.swift
// Form — Protocol-Based Exercise Analysis Engine
//
// This file defines the PUBLIC CONTRACT for all form analysis in the app.
// It answers the question: given a set of joint positions, how well is the
// user performing this exercise?
//
// ─── DESIGN: WHY A PROTOCOL? ────────────────────────────────────────────────
// Using a protocol (FormAnalyzing) instead of a single class means:
//   1. Each exercise (squat, deadlift, bench) has its OWN analyzer with its own rules
//   2. We can add new exercises without modifying existing code (Open/Closed Principle)
//   3. In tests, we can inject a MockAnalyzer that always returns .good
//
// The pattern is: protocol defines WHAT, concrete structs define HOW.
//
// ─── THE RULE ENGINE CONCEPT ─────────────────────────────────────────────────
// The second stage of Form's two-stage pipeline is a rule engine:
//   Stage 1: PoseDetector → [joint: position]     (Vision / neural network)
//   Stage 2: FormAnalyzer → FormFeedback           (geometry / rules)
//
// Stage 2 is deliberately simple: calculate joint angles using trigonometry,
// compare them to known-good ranges (e.g., "knee should be between 70°–100°
// at the bottom of a squat"), and produce feedback. No machine learning needed
// for this stage — biomechanics rules are well-established and interpretable.
//
// ─── OFFLINE PRINCIPLE ───────────────────────────────────────────────────────
// All rules run locally. The rule parameters (angle thresholds) are constants
// compiled into the app. There is no "cloud model" for the rule engine.

import Foundation
import Vision // For VNHumanBodyPoseObservation.JointName

// MARK: - ExerciseCameraSetup

/// Guidance on how the user should position their phone for a given exercise.
/// Shown as a "positioning" tip before a set so the joints the analyzer relies on
/// are actually visible to the camera.
struct ExerciseCameraSetup: Equatable {
    /// Short label for the framing, e.g. "Side-on" or "Face-on".
    let placement: String
    /// One-sentence instruction describing where to place the phone.
    let instruction: String
}

// MARK: - ExerciseType

/// The set of exercises the app can analyze.
///
/// Adding a new exercise means:
///   1. Add a case here
///   2. Create a new XxxAnalyzer struct conforming to FormAnalyzing
///   3. Register it in the factory function at the bottom of this file
///
/// Codable conformance lets ExerciseType serialize to/from JSON in Session.swift.
enum ExerciseType: String, Codable, CaseIterable, Identifiable {
    case squat         = "Squat"
    case deadlift      = "Deadlift"
    case bench         = "Bench Press"
    case latPulldown   = "Lat Pulldown"
    case dumbbellBench = "Dumbbell Bench"

    /// Identifiable conformance — required for ForEach in SwiftUI Pickers/Lists.
    var id: String { rawValue }

    /// Human-readable display name used in the UI.
    var displayName: String { rawValue }

    /// SF Symbol used to represent this exercise in selection UI.
    /// All names are valid on iOS 17+.
    var symbolName: String {
        switch self {
        case .squat:         return "figure.strengthtraining.functional"
        case .deadlift:      return "figure.strengthtraining.traditional"
        case .bench:         return "dumbbell.fill"
        case .latPulldown:   return "figure.cross.training"
        case .dumbbellBench: return "dumbbell.fill"
        }
    }

    /// Where to place the phone so the joints each analyzer needs are visible.
    ///
    /// This drives the "positioning" tip shown before a set starts. Pose detection
    /// is only as good as the framing: e.g. DumbbellBenchAnalyzer's wrist-alignment
    /// rule needs a side-on view, while LatPulldownAnalyzer assumes a face-on view
    /// (see the per-analyzer doc comments below).
    var cameraSetup: ExerciseCameraSetup {
        switch self {
        case .squat:
            return ExerciseCameraSetup(
                placement: "Face-on",
                instruction: "Stand facing the camera, a few steps back so your whole body — hips, knees and ankles — stays in frame."
            )
        case .deadlift:
            return ExerciseCameraSetup(
                placement: "Side-on",
                instruction: "Place the phone to your side at hip height so it sees your back, hips and knees in profile."
            )
        case .bench:
            return ExerciseCameraSetup(
                placement: "Side-on",
                instruction: "Prop the phone at the end of the bench, shooting along your side so it sees your shoulder, elbow and wrist."
            )
        case .latPulldown:
            return ExerciseCameraSetup(
                placement: "Face-on",
                instruction: "Set the phone in front of the machine at chest height so it sees both shoulders, elbows and wrists head-on."
            )
        case .dumbbellBench:
            return ExerciseCameraSetup(
                placement: "Side-on",
                instruction: "Prop the phone at the end of the bench, shooting from your side for the clearest view of elbow angle and wrist alignment."
            )
        }
    }

    /// The three joints that define the primary angle used by RepCounter.
    /// Returns (pointA, vertex, pointC) — RepCounter calls GeometryHelpers.angle(a:b:c:)
    /// where b is the vertex (the joint whose angle we're measuring).
    ///
    /// Rep cycle summary per exercise:
    ///   squat:         hip angle ~160° (stand) → ~70° (bottom) → ~160° (stand)
    ///   deadlift:      hip angle ~170° (stand) → ~70° (floor)  → ~170° (stand)
    ///   bench:         elbow angle ~160° (top) → ~70° (chest)  → ~160° (top)
    ///   latPulldown:   elbow angle ~160° (arms up) → ~60° (bar at chest) → ~160°
    ///   dumbbellBench: elbow angle ~160° (top) → ~70° (bottom) → ~160° (top)
    var repDetectionJoint: (VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName) {
        switch self {
        case .squat:
            return (.leftShoulder, .leftHip, .leftKnee)
        case .deadlift:
            return (.leftShoulder, .leftHip, .leftKnee)
        case .bench:
            return (.leftShoulder, .leftElbow, .leftWrist)
        case .latPulldown:
            // Elbow angle: tracks the arm pulling down from overhead
            // shoulder (top of upper arm) → elbow (vertex) → wrist (end of forearm)
            return (.leftShoulder, .leftElbow, .leftWrist)
        case .dumbbellBench:
            // Same elbow angle chain as barbell bench
            return (.leftShoulder, .leftElbow, .leftWrist)
        }
    }

    /// Suggested RepCounter thresholds for each exercise.
    /// These are starting-point values — per-user calibration will refine them.
    var repThresholds: (low: Double, high: Double) {
        switch self {
        case .squat:         return (low: 95,  high: 150)
        case .deadlift:      return (low: 95,  high: 155)
        case .bench:         return (low: 75,  high: 150)
        case .latPulldown:   return (low: 65,  high: 145)
        case .dumbbellBench: return (low: 75,  high: 150)
        }
    }
}

// MARK: - FormFeedback

/// The result of analyzing a single frame's joint positions.
///
/// WHY an enum instead of a struct?
/// The feedback has three fundamentally different shapes:
///   .good    — no data needed, everything is fine
///   .warning — needs a descriptive message (not an error, but fix it)
///   .error   — needs a descriptive message (likely to cause injury)
///
/// Associated values let each case carry its own payload. This is Swift's
/// version of discriminated unions / algebraic data types.
///
/// Usage in the UI:
///   switch feedback {
///   case .good:            showGreenBanner()
///   case .warning(let msg): showYellowBanner(msg)
///   case .error(let msg):  showRedBanner(msg)
///   }
enum FormFeedback: Equatable {
    case good
    case warning(String)
    case error(String)

    /// Convenience: the message to display in the UI banner.
    var message: String {
        switch self {
        case .good:              return "Good form! Keep going."
        case .warning(let msg):  return "⚠️ \(msg)"
        case .error(let msg):    return "🔴 \(msg)"
        }
    }

    /// Background color identifier for the feedback banner.
    var colorName: String {
        switch self {
        case .good:    return "feedbackGood"    // Green
        case .warning: return "feedbackWarning" // Amber
        case .error:   return "feedbackError"   // Red
        }
    }
}

// MARK: - FormAnalyzing Protocol

/// The contract that every exercise analyzer must fulfill.
///
/// Any struct or class conforming to FormAnalyzing can plug into WorkoutView's
/// analysis loop without any other changes. New exercises simply need a new conforming type.
protocol FormAnalyzing {
    /// The exercise this analyzer is specialized for.
    var exerciseType: ExerciseType { get }

    /// Given a snapshot of joint positions for the current frame, produce feedback.
    ///
    /// - Parameter joints: Joint positions in normalized view coordinates (0–1),
    ///   as output by PoseDetector. Keys are VNHumanBodyPoseObservation.JointName.
    ///   Not all joints are guaranteed to be present — check before using each one.
    ///
    /// - Returns: The form quality assessment for this frame.
    ///
    /// PERFORMANCE NOTE: This is called up to 30–60 times per second.
    /// Keep it fast: prefer simple trigonometry over loops or allocations.
    func analyze(joints: JointMap) -> FormFeedback
}

// MARK: - Geometry Helpers

/// Utility functions for joint angle calculations.
/// These are pure functions (no side effects) so they're free functions, not methods.
///
/// All joint angles are computed using the law of cosines / dot product formula
/// applied to 2D vectors, giving the interior angle at the vertex joint.
enum GeometryHelpers {

    /// Computes the angle at point B formed by the ray B→A and the ray B→C.
    ///
    /// This is the "joint angle" — for example, the knee angle is the angle at
    /// the knee joint between the thigh (hip→knee) and the shin (knee→ankle).
    ///
    /// - Parameters:
    ///   - a: First endpoint (e.g., hip point)
    ///   - b: Vertex (e.g., knee point) — the joint we're measuring
    ///   - c: Second endpoint (e.g., ankle point)
    /// - Returns: Angle in degrees (0–180). Returns 0 if a,b,c are coincident.
    static func angle(a: CGPoint, b: CGPoint, c: CGPoint) -> Double {
        // Create vectors FROM the vertex TO each endpoint
        let vectorBA = CGPoint(x: a.x - b.x, y: a.y - b.y)
        let vectorBC = CGPoint(x: c.x - b.x, y: c.y - b.y)

        // Dot product: v1 · v2 = |v1||v2|cos(θ)
        let dotProduct = vectorBA.x * vectorBC.x + vectorBA.y * vectorBC.y

        // Magnitudes (lengths) of each vector
        let magnitudeBA = sqrt(vectorBA.x * vectorBA.x + vectorBA.y * vectorBA.y)
        let magnitudeBC = sqrt(vectorBC.x * vectorBC.x + vectorBC.y * vectorBC.y)

        // Guard against division by zero (degenerate case: points are the same)
        guard magnitudeBA > 0, magnitudeBC > 0 else { return 0 }

        // Clamp to [-1, 1] to guard against floating point errors that could
        // push the value slightly outside acos's valid domain
        let cosTheta = (dotProduct / (magnitudeBA * magnitudeBC)).clamped(to: -1...1)

        // acos returns radians; convert to degrees for readability in debug logs
        return Double(acos(cosTheta) * 180 / .pi)
    }
}

extension Comparable {
    /// Clamps a value to a closed range. Usage: 1.5.clamped(to: 0...1) → 1.0
    func clamped(to range: ClosedRange<Self>) -> Self {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - SquatAnalyzer (First Concrete Implementation)

/// Analyzes squat form using joint angle thresholds.
///
/// CURRENT STATUS: STUB — rules are placeholders.
/// In a complete implementation, each rule would be calibrated against
/// certified personal trainer guidance and validated on real user data.
///
/// ─── SQUAT FORM RULES (to implement) ────────────────────────────────────────
/// Rule 1 — Knee cave (valgus): Left/right knee X position should stay outside
///   the corresponding hip's X position. Inward collapse increases ACL injury risk.
///
/// Rule 2 — Depth: Hip Y position should drop below knee Y at the bottom of the
///   rep. "Below parallel" is the standard depth for a full squat.
///
/// Rule 3 — Forward lean: The angle at the hip (shoulder→hip→knee) indicates how
///   much the torso is bent forward. Excessive forward lean stresses the lower back.
///
/// Rule 4 — Heel lift: Ankle position stability across frames. If heel Y coordinate
///   rises, the user is shifting weight forward (often a mobility issue).
struct SquatAnalyzer: FormAnalyzing {
    var exerciseType: ExerciseType { .squat }

    func analyze(joints: JointMap) -> FormFeedback {
        // ── Guard: need at minimum hip and knee joints ──────────────────────
        guard
            let leftHip   = joints[.leftHip],
            let leftKnee  = joints[.leftKnee],
            let rightHip  = joints[.rightHip],
            let rightKnee = joints[.rightKnee]
        else {
            // If key joints aren't visible, we can't analyze — stay neutral.
            return .good
        }

        // ── Stub Rule: Knee Cave Detection ──────────────────────────────────
        // A proper knee cave check compares knee X to hip X.
        // For now we check a simplified proxy: knee X should be >= hip X (in
        // mirrored front camera view, "outside" means larger X for left side,
        // smaller X for right side).
        //
        // TODO: Refine thresholds after testing on real users.
        let leftKneeCaved  = leftKnee.x < leftHip.x - 0.05
        let rightKneeCaved = rightKnee.x > rightHip.x + 0.05

        if leftKneeCaved || rightKneeCaved {
            return .warning("Keep your knees tracking over your toes.")
        }

        // ── Stub Rule: Hip Depth ─────────────────────────────────────────────
        // In normalized coordinates, Y increases downward (we flipped in PoseDetector).
        // When squatting, hips move DOWN (Y increases). Below parallel means
        // hip Y > knee Y.
        //
        // This rule only fires when the user IS squatting (hip is low enough
        // to indicate they're in the descent/hole). We skip it when standing.
        // TODO: Use hip angle over time to determine phase (descent vs ascent vs standing).
        let avgHipY  = (leftHip.y + joints[.rightHip]!.y) / 2
        let avgKneeY = (leftKnee.y + rightKnee.y) / 2

        // Only check depth if hips are more than 20% below their neutral position
        // (naive heuristic — replace with phase detection later)
        if avgHipY > 0.5 && avgHipY < avgKneeY - 0.05 {
            return .warning("Squat deeper — aim for hips below parallel.")
        }

        // All stub checks pass
        return .good
    }
}

// MARK: - Deadlift Analyzer Stub

/// Stub for deadlift form analysis.
/// Key rules to implement:
///   - Back rounding: shoulder→hip angle should stay near neutral spine (~180°)
///   - Bar path: wrist X deviation from hip X (bar should stay over mid-foot)
///   - Hip hinge pattern: hip angle change vs knee angle change ratio
struct DeadliftAnalyzer: FormAnalyzing {
    var exerciseType: ExerciseType { .deadlift }

    func analyze(joints: JointMap) -> FormFeedback {
        // TODO: Implement spine angle detection (shoulder→hip vector angle from vertical)
        // TODO: Implement bar path tracking using wrist positions across frames
        return .good
    }
}

// MARK: - Bench Press Analyzer Stub

/// Stub for barbell bench press form analysis.
/// Key rules to implement:
///   - Elbow flare: elbow X should stay within ~45° of body axis
///   - Bar path: wrist path should track in an arc, not purely vertical
///   - Wrist alignment: wrist should stay above elbow
struct BenchAnalyzer: FormAnalyzing {
    var exerciseType: ExerciseType { .bench }

    func analyze(joints: JointMap) -> FormFeedback {
        // TODO: Implement elbow angle tracking and wrist alignment checks
        return .good
    }
}

// MARK: - Lat Pulldown Analyzer

/// Analyzes lat pulldown form.
///
/// ─── EXERCISE OVERVIEW ───────────────────────────────────────────────────────
/// The lat pulldown is a seated, cable-based pulling exercise.
/// The user grabs a bar overhead and pulls it down to their upper chest.
/// Camera position: directly in front of the user (face-on view).
///
/// ─── JOINT VISIBILITY ───────────────────────────────────────────────────────
/// Because the user is seated and pulling from overhead, the following joints
/// are reliably visible from a front-facing iPhone camera:
///   shoulders, elbows, wrists (the pulling chain)
///   left/right shoulders (grip width proxy)
/// Hips and legs are less useful — the machine obscures them.
///
/// ─── FORM RULES IMPLEMENTED ──────────────────────────────────────────────────
/// Rule 1 — ELBOW ANGLE at bottom: The elbow angle (shoulder→elbow→wrist)
///   should reach ~60–75° at the bottom of the pull. Much higher = incomplete
///   range of motion (not engaging the lats fully). Much lower = forced/jerky pull.
///
/// Rule 2 — SHOULDER SHRUG check: At the bottom of the pull, shoulders should
///   be DEPRESSED (pulled DOWN and back), not shrugged up toward the ears.
///   We detect this by comparing shoulder Y to a baseline established at the
///   top of the rep. If shoulders rise at the bottom, that's a shrug.
///   WHY IT MATTERS: A shrugged shoulder means the traps are doing the work
///   instead of the lats — the entire point of the exercise is lost.
///
/// Rule 3 — GRIP SYMMETRY: The left and right wrists should be at roughly the
///   same height throughout the movement. Asymmetry means one arm is pulling
///   harder — a muscular imbalance indicator.
///
/// Rule 4 — ELBOW FLARE / TUCK: Elbows should flare OUT to the sides, not
///   pull straight down in front of the body (that's a tricep pushdown, not
///   a lat pulldown). We check elbow X relative to wrist X.
struct LatPulldownAnalyzer: FormAnalyzing {
    var exerciseType: ExerciseType { .latPulldown }

    // Shoulder Y baseline established when arms are extended overhead (start of rep).
    // We track this to detect shrugging during the pull.
    // NOTE: This is mutable state in an analyzer — not ideal for pure functional design.
    // A future refactor would pass phase + history into analyze() as parameters.
    private var shoulderBaselineY: Double? = nil

    func analyze(joints: JointMap) -> FormFeedback {
        // ── Require the core pulling chain ──────────────────────────────────
        guard
            let leftShoulder  = joints[.leftShoulder],
            let rightShoulder = joints[.rightShoulder],
            let leftElbow     = joints[.leftElbow],
            let rightElbow    = joints[.rightElbow],
            let leftWrist     = joints[.leftWrist],
            let rightWrist    = joints[.rightWrist]
        else { return .good }

        // ── Rule 1: Elbow angle at the bottom of the pull ───────────────────
        // We compute BOTH sides and use the average — the bar forces bilateral symmetry.
        let leftElbowAngle  = GeometryHelpers.angle(a: leftShoulder,  b: leftElbow,  c: leftWrist)
        let rightElbowAngle = GeometryHelpers.angle(a: rightShoulder, b: rightElbow, c: rightWrist)
        let avgElbowAngle   = (leftElbowAngle + rightElbowAngle) / 2

        // Only check range of motion when the user IS pulling (elbow bent past 90°).
        // At >100° the arms are still mostly extended — that's the top position, skip.
        if avgElbowAngle < 100 {
            // Bottom of pull — check that they're pulling deep enough
            if avgElbowAngle > 80 {
                // Elbow is still too open — they stopped short. Under 80° is ideal bottom.
                return .warning("Pull the bar all the way to your chest — elbows deeper.")
            }
        }

        // ── Rule 2: Shoulder Shrug Detection ────────────────────────────────
        // At the top (arms extended), record the shoulder Y as baseline.
        // At the bottom (elbow angle < 80°), if shoulder Y has DECREASED (moved UP
        // toward the camera top = shrugging), fire a warning.
        //
        // In our coordinate system: Y=0 is top of screen, Y=1 is bottom.
        // Shrugging = shoulders move UP = Y DECREASES.
        let avgShoulderY = (leftShoulder.y + rightShoulder.y) / 2

        // When arms are extended overhead (top of rep), shoulders should be at their
        // lowest Y (most elevated in the frame). This is the baseline.
        // We detect shrug at the bottom by checking if avgShoulderY drops significantly
        // below the mid-frame position (which would mean shoulders rose toward ears).
        //
        // Heuristic: if shoulder Y < 0.35 (very high in frame), they're shrugging.
        // TODO: Replace with dynamic baseline calibrated from user's first rep.
        if avgElbowAngle < 80 && avgShoulderY < 0.35 {
            return .error("Don't shrug! Pull your shoulders DOWN and back as you pull.")
        }

        // ── Rule 3: Grip Symmetry ────────────────────────────────────────────
        // Left and right wrists should be at the same Y (same height).
        // A >0.07 normalized unit difference = ~7% of screen height — noticeable asymmetry.
        let wristHeightDiff = abs(leftWrist.y - rightWrist.y)
        if wristHeightDiff > 0.07 {
            return .warning("Keep both arms even — one side is pulling higher.")
        }

        // ── Rule 4: Elbow Flare Check ────────────────────────────────────────
        // For lat pulldown, elbows should be WIDER than wrists (elbows flared out).
        // If elbows are NARROWER than wrists, the user is doing a close-grip tricep pull.
        // We check: leftElbow.x < leftWrist.x (left elbow is to the LEFT of left wrist).
        // In our mirrored front-camera view, "wider" means smaller X for left, larger for right.
        let leftElbowFlared  = leftElbow.x  < leftWrist.x  - 0.03
        let rightElbowFlared = rightElbow.x > rightWrist.x + 0.03

        if !leftElbowFlared && !rightElbowFlared && avgElbowAngle < 90 {
            // At the bottom of the pull, elbows should definitely be flared
            return .warning("Flare your elbows out to the sides — you'll feel it in your lats.")
        }

        return .good
    }
}

// MARK: - Dumbbell Bench Press Analyzer

/// Analyzes dumbbell bench press form.
///
/// ─── EXERCISE OVERVIEW ───────────────────────────────────────────────────────
/// The dumbbell bench press is performed lying on a flat bench, pressing two
/// dumbbells from chest level to full arm extension overhead.
/// Camera position: the user props their phone up at the end of the bench,
/// shooting from the side (sagittal plane view). This gives the best view
/// of elbow angle and wrist alignment.
///
/// WHY DUMBBELL BENCH IS BETTER TO ANALYZE THAN BARBELL BENCH:
/// With dumbbells, each arm moves independently — bilateral asymmetry is
/// immediately visible and quantifiable. Barbell forces symmetric movement.
///
/// ─── FORM RULES IMPLEMENTED ──────────────────────────────────────────────────
/// Rule 1 — ELBOW ANGLE at bottom: Should be ~70–80° at the bottom (chest level).
///   Too open (>90°) = user isn't getting full stretch on the pecs.
///   Too closed (<50°) = elbows are flaring forward, stressing the shoulder joint.
///
/// Rule 2 — ELBOW FLARE (horizontal): In a side-on view, elbow X relative to
///   shoulder X indicates how far the elbows are out. Elbows should be at ~45°
///   from the torso — not 90° (shoulder impingement risk) and not 0° (no chest activation).
///
/// Rule 3 — WRIST ALIGNMENT: Wrists should stay directly above elbows throughout
///   the press. A bent wrist (wrist X behind elbow X in side view) indicates the
///   user is compensating for wrist weakness — injury risk under load.
///
/// Rule 4 — BILATERAL SYMMETRY: Left vs right elbow angles should be within ~15°
///   of each other. Greater asymmetry = dominant side compensating.
///   This is the PRIMARY advantage of dumbbell over barbell — we CAN detect this.
struct DumbbellBenchAnalyzer: FormAnalyzing {
    var exerciseType: ExerciseType { .dumbbellBench }

    func analyze(joints: JointMap) -> FormFeedback {
        // ── Require both arm chains ──────────────────────────────────────────
        guard
            let leftShoulder  = joints[.leftShoulder],
            let rightShoulder = joints[.rightShoulder],
            let leftElbow     = joints[.leftElbow],
            let rightElbow    = joints[.rightElbow],
            let leftWrist     = joints[.leftWrist],
            let rightWrist    = joints[.rightWrist]
        else { return .good }

        // ── Rule 4 (check first — highest safety priority): Bilateral Symmetry ─
        // Compute elbow angles for BOTH arms independently.
        let leftElbowAngle  = GeometryHelpers.angle(a: leftShoulder,  b: leftElbow,  c: leftWrist)
        let rightElbowAngle = GeometryHelpers.angle(a: rightShoulder, b: rightElbow, c: rightWrist)

        // Only check symmetry during the active press (not at full extension).
        // At full extension both angles are ~160°+ — small differences don't matter.
        let isPressingPhase = leftElbowAngle < 140 || rightElbowAngle < 140

        if isPressingPhase {
            let asymmetry = abs(leftElbowAngle - rightElbowAngle)
            if asymmetry > 20 {
                // >20° difference is significant — one arm is clearly ahead of the other
                let laggingSide = leftElbowAngle < rightElbowAngle ? "left" : "right"
                return .error("\(laggingSide.capitalized) arm is lagging — keep both dumbbells at the same height.")
            }
        }

        // ── Rule 1: Elbow Angle at Bottom ───────────────────────────────────
        let avgElbowAngle = (leftElbowAngle + rightElbowAngle) / 2

        // At the bottom of the press (elbow angle < 90°, dumbbells near chest)
        if avgElbowAngle < 90 {
            if avgElbowAngle > 85 {
                // They're stopping too high — not getting chest stretch
                return .warning("Lower the dumbbells more — get a full stretch at the bottom.")
            }
            if avgElbowAngle < 45 {
                // Elbows are dangerously tucked — unusual but flag it
                return .warning("Don't drop elbows too low — control the descent.")
            }
        }

        // ── Rule 3: Wrist Alignment over Elbow ──────────────────────────────
        // From a side/front view, wrist X should be close to elbow X.
        // If wrist X is significantly BEHIND elbow X (wrist dropping back),
        // that's a bent wrist = load going through the joint, not the palm.
        //
        // We check the average wrist-to-elbow X delta.
        // NOTE: In a front-on camera view this is less reliable than side view.
        // TODO: Prompt user to film from the side for best wrist alignment detection.
        let leftWristElbowDelta  = abs(leftWrist.x  - leftElbow.x)
        let rightWristElbowDelta = abs(rightWrist.x - rightElbow.x)
        let maxWristDrift        = max(leftWristElbowDelta, rightWristElbowDelta)

        // >0.10 normalized units of wrist drift from elbow = noticeably bent wrist
        if maxWristDrift > 0.10 && isPressingPhase {
            return .warning("Keep your wrists straight — don't let them bend back.")
        }

        // ── Rule 2: Elbow Flare ──────────────────────────────────────────────
        // From a front-on view, elbow X vs shoulder X tells us flare angle.
        // Elbows should be OUTSIDE the shoulder line but not excessively so.
        // "Too tucked" = elbows are INSIDE shoulder X (close to body)
        // "Too flared" = elbows are MUCH wider than shoulders (>0.15 units outside)
        //
        // NOTE: This rule is most useful from a side view. From the front it's
        // a proxy. TODO: Add camera positioning guidance to UI.
        let leftFlare  = leftShoulder.x  - leftElbow.x   // positive = elbow inside shoulder
        let rightFlare = rightElbow.x - rightShoulder.x  // positive = elbow outside shoulder

        if isPressingPhase {
            if leftFlare > 0.10 || rightFlare < -0.10 {
                return .warning("Don't tuck your elbows too tight — about 45° from your torso.")
            }
        }

        return .good
    }
}

// MARK: - Factory Function

/// Returns the appropriate FormAnalyzing implementation for a given exercise.
///
/// This is the Factory Method pattern: callers ask for an analyzer by exercise type
/// and get back a fully configured analyzer without knowing the concrete type.
/// Adding a new exercise = add one case here + create the analyzer struct above.
func makeAnalyzer(for exercise: ExerciseType) -> any FormAnalyzing {
    switch exercise {
    case .squat:         return SquatAnalyzer()
    case .deadlift:      return DeadliftAnalyzer()
    case .bench:         return BenchAnalyzer()
    case .latPulldown:   return LatPulldownAnalyzer()
    case .dumbbellBench: return DumbbellBenchAnalyzer()
    }
}
