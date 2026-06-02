// ExerciseSelectionView.swift
// Form — Dedicated Exercise Picker (A/B variant)
//
// One of two exercise-selection UIs (see ExerciseSelectionStyle). This full-screen
// variant is shown BEFORE the camera: a grid of exercise cards, each with its icon,
// name, and a hint of the camera framing it expects. Tapping a card hands the choice
// back to WorkoutView via `onSelect`, which sets AppState.selectedExercise — and that
// in turn dismisses this screen (WorkoutView stops rendering it once a pick exists).
//
// It draws on a dark background because it sits over the (black) camera layer; the
// styling deliberately echoes the workout HUD.

import SwiftUI

// MARK: - ExerciseSelectionView

struct ExerciseSelectionView: View {

    /// Called with the exercise the user tapped.
    let onSelect: (ExerciseType) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose an exercise")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                    Text("Form will coach your technique in real time.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(ExerciseType.allCases) { exercise in
                            ExerciseCard(exercise: exercise) {
                                onSelect(exercise)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

// MARK: - Exercise Card

/// A tappable card representing one exercise on the dedicated selection screen.
struct ExerciseCard: View {
    let exercise: ExerciseType
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: exercise.symbolName)
                    .font(.system(size: 32))
                    .foregroundColor(.orange)

                Text(exercise.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)

                // Framing hint pulled from the same source as the in-set tip.
                Label(exercise.cameraSetup.placement, systemImage: "camera.viewfinder")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(16)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}
