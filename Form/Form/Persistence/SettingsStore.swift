// SettingsStore.swift
// Form — User Preferences Persistence
//
// Small, app-wide preferences live here: the spoken-cue voice (see VoicePreferences)
// and which exercise-selection UI to show. Unlike SessionStore — which persists an
// array of rich domain objects to a JSON file — these are a handful of tiny scalar
// settings, exactly the case UserDefaults exists for.
//
// The store is an ObservableObject created once at app launch (FormApp) and injected
// via @EnvironmentObject. Mutating a @Published property both re-renders observing
// views AND writes through to UserDefaults via didSet, so settings survive relaunch.
//
// ─── TESTABILITY ──────────────────────────────────────────────────────────────
// The backing UserDefaults is injected (defaults to .standard) so the headless test
// harness can pass an isolated suite and assert round-trips without touching the
// real user domain. Foundation's UserDefaults is available off-device, keeping this
// on the testable side of the hardware boundary (see CLAUDE.md).

import Foundation
import Combine

// MARK: - ExerciseSelectionStyle

/// Which UI the user sees for choosing an exercise. Two variants are shipped so the
/// product can be A/B tested; the choice is just a persisted preference.
enum ExerciseSelectionStyle: String, Codable, CaseIterable, Identifiable {
    /// A full, dedicated screen of exercise cards shown before the camera.
    case dedicatedScreen = "Dedicated Screen"
    /// A compact picker embedded in the workout HUD over the live camera.
    case inlinePicker    = "Inline Picker"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

// MARK: - SettingsStore

/// Persists app-wide user preferences to UserDefaults.
final class SettingsStore: ObservableObject {

    // MARK: - Published Settings

    /// Voice/pitch/rate for spoken coaching cues. Written through on change.
    @Published var voice: VoicePreferences {
        didSet { persistVoice() }
    }

    /// Which exercise-selection UI to present. Written through on change.
    @Published var exerciseSelectionStyle: ExerciseSelectionStyle {
        didSet { defaults.set(exerciseSelectionStyle.rawValue, forKey: Keys.exerciseSelectionStyle) }
    }

    // MARK: - Backing Store

    private let defaults: UserDefaults

    private enum Keys {
        static let voice = "form.settings.voice"
        static let exerciseSelectionStyle = "form.settings.exerciseSelectionStyle"
    }

    // MARK: - Init

    /// - Parameter defaults: inject an isolated suite in tests; defaults to `.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Voice: decode the stored JSON blob, falling back to the default character
        // if absent or corrupt. (VoicePreferences re-clamps on decode.)
        if let data = defaults.data(forKey: Keys.voice),
           let decoded = try? JSONDecoder().decode(VoicePreferences.self, from: data) {
            self.voice = decoded
        } else {
            self.voice = .default
        }

        // Selection style: a raw String; fall back to the dedicated screen.
        if let raw = defaults.string(forKey: Keys.exerciseSelectionStyle),
           let style = ExerciseSelectionStyle(rawValue: raw) {
            self.exerciseSelectionStyle = style
        } else {
            self.exerciseSelectionStyle = .dedicatedScreen
        }
    }

    // MARK: - Persistence

    private func persistVoice() {
        if let data = try? JSONEncoder().encode(voice) {
            defaults.set(data, forKey: Keys.voice)
        }
    }
}
