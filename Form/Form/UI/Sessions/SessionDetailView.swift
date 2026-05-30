// SessionDetailView.swift
// Form — Rep-by-Rep Session Breakdown

import SwiftUI

// MARK: - SessionDetailView

/// Shows every rep in a session with its form score, timestamp, and dominant error.
///
/// This view is read-only — sessions are not editable, only viewable.
struct SessionDetailView: View {
    let session: Session

    var body: some View {
        List {
            // MARK: Summary Header
            Section {
                VStack(spacing: 12) {
                    // Grade circle
                    if let score = session.formScore {
                        ZStack {
                            Circle()
                                .fill(gradeColor(score.grade).opacity(0.15))
                                .frame(width: 100, height: 100)
                            VStack(spacing: 2) {
                                Text(score.grade)
                                    .font(.system(size: 44, weight: .black, design: .rounded))
                                    .foregroundColor(gradeColor(score.grade))
                                Text("GRADE")
                                    .font(.caption2.bold())
                                    .foregroundColor(.secondary)
                                    .tracking(3)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // Stats row
                        HStack(spacing: 32) {
                            StatCell(label: "Reps", value: "\(score.repCount)")
                            StatCell(label: "Avg Score", value: String(format: "%.0f", score.averageScore))
                            StatCell(label: "Exercise", value: session.exerciseType.displayName)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 8)
            }

            // MARK: Notes
            if let notes = session.notes {
                Section("Notes") {
                    Text(notes)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            // MARK: Rep List
            Section("Reps") {
                if session.reps.isEmpty {
                    Text("No reps recorded in this session.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(session.reps.enumerated()), id: \.element.id) { index, rep in
                        RepRowView(repNumber: index + 1, rep: rep)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(session.exerciseType.displayName)
        .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Rep Row View

/// Displays a single rep: number, score bar, and dominant error.
struct RepRowView: View {
    let repNumber: Int
    let rep: Rep

    var body: some View {
        HStack(spacing: 12) {
            // Rep number badge
            Text("#\(repNumber)")
                .font(.caption.bold())
                .frame(width: 32)
                .foregroundColor(.secondary)

            // Score bar
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(scoreColor(rep.formScore))
                            .frame(width: geo.size.width * CGFloat(rep.formScore) / 100)
                    }
                }
                .frame(height: 8)

                if let error = rep.dominantError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Score number
            Text("\(rep.formScore)")
                .font(.callout.bold())
                .foregroundColor(scoreColor(rep.formScore))
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80:  return .orange
        default:       return .red
        }
    }
}

// MARK: - Stat Cell

/// Compact labeled statistic — used in the session summary header.
struct StatCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .tracking(1)
        }
    }
}
