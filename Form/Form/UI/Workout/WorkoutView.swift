// WorkoutView.swift
// Form — Root Workout Screen
//
// This is the primary feature view: it orchestrates the live camera feed,
// skeleton overlay, form feedback banner, and rep counter into one screen.
//
// ─── COMPONENT RELATIONSHIPS ─────────────────────────────────────────────────
//
//   WorkoutView
//   ├── CameraPreviewView   (UIKit: AVCaptureVideoPreviewLayer)
//   ├── SkeletonOverlayView (SwiftUI Canvas: joint dots + bone lines)
//   ├── FeedbackBannerView  (SwiftUI: colored banner with form cue text)
//   └── WorkoutHUDView      (SwiftUI: rep counter, exercise name, start/stop)
//
// ─── DATA FLOW ────────────────────────────────────────────────────────────────
//
//   CameraManager ──(CMSampleBuffer)──▶ PoseDetector ──(JointMap)──▶
//     ├── SkeletonOverlayView (render)
//     ├── FormAnalyzer (analyze) ──▶ FormFeedback ──▶ FeedbackBannerView
//     └── RepCounter (count) ──▶ repCompleted ──▶ AppState.recordRep()
//
// ─── STATE OWNERSHIP ──────────────────────────────────────────────────────────
// WorkoutView owns CameraManager, PoseDetector, RepCounter, AudioCueEngine.
// These are @StateObject — created once and kept alive as long as this view exists.
// When the user navigates away, they're deallocated, stopping the camera.

import SwiftUI
import AVFoundation
import Combine

// MARK: - WorkoutView

struct WorkoutView: View {

    // MARK: - Environment

    @EnvironmentObject var appState: AppState

    // MARK: - State Objects (owned by this view)

    /// Camera pipeline — starts when view appears, stops when it disappears.
    @StateObject private var cameraManager = CameraManager()

    /// Processes camera frames into joint positions.
    @StateObject private var poseDetector = PoseDetector()

    /// Counts reps from joint angle changes.
    @StateObject private var repCounter = RepCounter()

    /// Speaks form cues aloud.
    @StateObject private var audioCue = AudioCueEngine()

    // MARK: - Local State

    /// The active form analyzer (changes when the user selects a different exercise).
    @State private var analyzer: (any FormAnalyzing)? = nil

    /// Combine subscription bag. All subscriptions are cancelled when this is deallocated,
    /// which automatically happens when the view disappears. This prevents memory leaks.
    @State private var cancellables = Set<AnyCancellable>()

    // MARK: - SessionStore (for saving completed sessions)
    // Shared instance injected from FormApp — the same store History reads from.
    @EnvironmentObject private var store: SessionStore

    // MARK: - SettingsStore (voice + exercise-selection UI preferences)
    // Shared instance injected from FormApp.
    @EnvironmentObject private var settings: SettingsStore

    /// True when the dedicated exercise-selection screen should cover the camera:
    /// the user picked that variant, hasn't chosen an exercise, and isn't mid-set.
    private var needsDedicatedSelection: Bool {
        settings.exerciseSelectionStyle == .dedicatedScreen
            && appState.selectedExercise == nil
            && !appState.isSessionActive
    }

    // MARK: - View Body

    var body: some View {
        NavigationStack {
            ZStack {
                // ── Layer 1: Black background (visible before camera starts) ──
                Color.black.ignoresSafeArea()

                // ── Layer 2: Live camera feed ──────────────────────────────────
                if cameraManager.permissionGranted {
                    CameraPreviewView(session: cameraManager.session)
                        .ignoresSafeArea()
                } else {
                    // Camera permission denied — show explanation
                    permissionDeniedView
                }

                // ── Layer 3: Skeleton overlay (transparent, drawn on top of feed) ─
                SkeletonOverlayView(joints: poseDetector.currentJoints)
                    .ignoresSafeArea()

                // ── Layer 4: HUD elements ──────────────────────────────────────
                VStack(spacing: 12) {
                    // Form feedback banner at the top
                    FeedbackBannerView(feedback: appState.latestFeedback)
                        .padding(.top, 60) // Below the notch/dynamic island

                    Spacer()

                    // Camera-positioning tip — shown once an exercise is chosen but
                    // before the set starts, in BOTH selection variants.
                    if !appState.isSessionActive, let exercise = appState.selectedExercise {
                        CameraSetupCard(exercise: exercise)
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Workout controls at the bottom
                    WorkoutHUDView(
                        repCount: appState.liveRepCount,
                        isActive: appState.isSessionActive,
                        selectedExercise: $appState.selectedExercise,
                        showInlinePicker: settings.exerciseSelectionStyle == .inlinePicker,
                        onStart: startWorkout,
                        onStop: stopWorkout,
                        onChangeExercise: { appState.selectedExercise = nil }
                    )
                    .padding(.bottom, 40) // Above home indicator
                }
                .animation(.spring(duration: 0.3), value: appState.selectedExercise)

                // ── Layer 5: Dedicated exercise-selection screen (A/B variant) ──
                // Covers the camera until an exercise is chosen.
                if needsDedicatedSelection {
                    ExerciseSelectionView { exercise in
                        appState.selectedExercise = exercise
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: needsDedicatedSelection)
            .navigationTitle("Form")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black.opacity(0.5), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        // MARK: - Lifecycle
        .onAppear {
            setupPipeline()
            audioCue.apply(settings.voice)
            cameraManager.startSession()
        }
        // Keep the audio engine in sync if the user edits voice settings while
        // this view is alive (e.g. switches tabs to Settings and back).
        .onChange(of: settings.voice) { _, newValue in
            audioCue.apply(newValue)
        }
        .onDisappear {
            cameraManager.stopSession()
            cancellables.removeAll()
        }
    }

    // MARK: - Setup

    /// Wires together the processing pipeline:
    ///   CameraManager → PoseDetector → (FormAnalyzer + RepCounter)
    private func setupPipeline() {
        // Connect camera output to pose detector
        cameraManager.delegate = poseDetector

        // Subscribe to PoseDetector's joint publisher.
        // Every new JointMap triggers form analysis and rep counting.
        poseDetector.jointPublisher
            .receive(on: DispatchQueue.main) // Switch to main for UI updates
            .sink { [weak appState] joints in
                guard let appState, appState.isSessionActive,
                      let exercise = appState.selectedExercise else { return }

                // Form analysis
                if let analyzer = self.analyzer {
                    let feedback = analyzer.analyze(joints: joints)
                    appState.latestFeedback = feedback

                    // Speak audio cues for non-good feedback
                    if case .warning(let msg) = feedback {
                        self.audioCue.enqueue(cue: msg)
                    } else if case .error(let msg) = feedback {
                        self.audioCue.enqueue(cue: msg)
                    }
                }

                // Rep counting
                self.repCounter.update(joints: joints, exercise: exercise)
            }
            .store(in: &cancellables)

        // Subscribe to rep completion events
        repCounter.repCompleted
            .receive(on: DispatchQueue.main)
            .sink { [weak appState] in
                guard let appState else { return }
                // Create a Rep with the current feedback as the dominant error
                let dominantError: String? = {
                    switch appState.latestFeedback {
                    case .good: return nil
                    case .warning(let msg), .error(let msg): return msg
                    }
                }()

                // Compute a simple form score: good=100, warning=70, error=40
                let score: Int = {
                    switch appState.latestFeedback {
                    case .good: return 100
                    case .warning: return 70
                    case .error: return 40
                    }
                }()

                let rep = Rep(formScore: score, dominantError: dominantError)
                appState.recordRep(rep)
            }
            .store(in: &cancellables)
    }

    // MARK: - Workout Control

    private func startWorkout() {
        guard let exercise = appState.selectedExercise else { return }
        analyzer = makeAnalyzer(for: exercise)
        repCounter.configure(for: exercise)
        appState.startSession(for: exercise)
        audioCue.enqueue(cue: "Starting \(exercise.displayName) analysis.")
    }

    private func stopWorkout() {
        if let session = appState.endSession() {
            store.save(session: session)
        }
        audioCue.stopAll()
        analyzer = nil
    }

    // MARK: - Permission Denied View

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            Text("Camera Access Required")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("Form needs camera access to analyze your exercise technique. All processing happens on your device — no video is ever uploaded.")
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
    }
}

// MARK: - Feedback Banner View

/// Displays the current FormFeedback as a colored banner.
struct FeedbackBannerView: View {
    let feedback: FormFeedback

    var body: some View {
        HStack {
            Text(feedback.message)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(bannerColor.opacity(0.85))
        .clipShape(Capsule())
        .shadow(color: bannerColor.opacity(0.4), radius: 8, y: 4)
        .animation(.spring(duration: 0.3), value: feedback.message)
    }

    private var bannerColor: Color {
        switch feedback {
        case .good:    return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }
}

// MARK: - Workout HUD View

/// Bottom-of-screen controls: exercise picker, rep counter, start/stop button.
struct WorkoutHUDView: View {
    let repCount: Int
    let isActive: Bool
    @Binding var selectedExercise: ExerciseType?
    /// True for the inline-picker A/B variant. False when the dedicated selection
    /// screen owns exercise choice (the HUD then just shows the current pick).
    let showInlinePicker: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    /// Clears the current selection so the user can pick a different exercise.
    let onChangeExercise: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Rep counter display
            if isActive {
                Text("\(repCount)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                Text("REPS")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(4)
            }

            // Exercise selection (only before a set starts)
            if !isActive {
                if showInlinePicker {
                    // ── A/B variant: inline scrollable cards over the camera ──
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ExerciseType.allCases) { exercise in
                                ExerciseChip(
                                    exercise: exercise,
                                    isSelected: exercise == selectedExercise
                                ) {
                                    selectedExercise = exercise
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                } else if let exercise = selectedExercise {
                    // ── Dedicated-screen variant: show the pick + a way back ──
                    HStack(spacing: 12) {
                        Image(systemName: exercise.symbolName)
                            .foregroundColor(.orange)
                        Text(exercise.displayName)
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Button("Change", action: onChangeExercise)
                            .font(.subheadline.weight(.semibold))
                            .tint(.orange)
                    }
                    .padding(.horizontal)
                }
            }

            // Start / Stop button
            Button(action: isActive ? onStop : onStart) {
                Label(
                    isActive ? "Stop Workout" : "Start Workout",
                    systemImage: isActive ? "stop.fill" : "play.fill"
                )
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isActive ? Color.red : Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }
            .disabled(!isActive && selectedExercise == nil)
        }
        .padding(.vertical, 20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 16)
    }
}

// MARK: - Exercise Chip (inline picker variant)

/// A compact, selectable exercise card used in the inline HUD picker.
struct ExerciseChip: View {
    let exercise: ExerciseType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: exercise.symbolName)
                    .font(.title3)
                Text(exercise.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .black : .white)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(isSelected ? Color.orange : Color.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Camera Setup Card (positioning guidance)

/// Shows where to place the phone for the selected exercise before a set starts.
/// Backed by ExerciseType.cameraSetup so each exercise gets framing that matches
/// the joints its analyzer relies on.
struct CameraSetupCard: View {
    let exercise: ExerciseType

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.title2)
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(exercise.cameraSetup.placement) view")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text(exercise.cameraSetup.instruction)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
