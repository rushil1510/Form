// SessionListView.swift
// Form — History: List of Past Sessions

import SwiftUI

// MARK: - SessionListView

/// Displays all past workout sessions, grouped by exercise type.
/// Tapping a session navigates to SessionDetailView for rep-by-rep breakdown.
struct SessionListView: View {

    @StateObject private var store = SessionStore()

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(ExerciseType.allCases) { exercise in
                            let sessionsForExercise = store.sessions.filter {
                                $0.exerciseType == exercise
                            }
                            if !sessionsForExercise.isEmpty {
                                Section(exercise.displayName) {
                                    ForEach(sessionsForExercise) { session in
                                        NavigationLink(destination: SessionDetailView(session: session)) {
                                            SessionRowView(session: session)
                                        }
                                    }
                                    .onDelete { offsets in
                                        // Map section-local offsets back to global store offsets
                                        let globalOffsets = IndexSet(
                                            offsets.map { i in
                                                store.sessions.firstIndex(where: { $0.id == sessionsForExercise[i].id })!
                                            }
                                        )
                                        store.delete(at: globalOffsets)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 64))
                .foregroundColor(.orange.opacity(0.6))
            Text("No Sessions Yet")
                .font(.title2.bold())
            Text("Complete a workout to see your history here.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

// MARK: - Session Row View

/// Compact row showing session summary: exercise, date, score, rep count.
struct SessionRowView: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.displayDate)
                    .font(.subheadline.bold())
                Spacer()
                // Score badge
                if let score = session.formScore {
                    Text(score.grade)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(gradeColor(score.grade).opacity(0.2))
                        .foregroundColor(gradeColor(score.grade))
                        .clipShape(Capsule())
                }
            }
            Text("\(session.reps.count) rep\(session.reps.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return .green
        case "B": return .blue
        case "C": return .orange
        default:  return .red
        }
    }
}
