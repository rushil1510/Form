// SettingsView.swift
// Form — User Preferences Screen
//
// Lets the user shape two things that came up in testing:
//   1. The coaching VOICE — which voice, how deep (pitch), how fast (rate). The
//      default is a slightly low, slightly slow locale voice; some users want it
//      deeper or want a specific named voice.
//   2. The exercise-SELECTION UI — a dedicated screen vs. an inline picker. Both
//      ship so the product can be A/B tested; this toggle picks the active one.
//
// All changes write through SettingsStore to UserDefaults immediately (its @Published
// setters persist on didSet), so there's no explicit "Save" button. The "Test voice"
// button speaks a sample with the live preferences via a self-contained previewer so
// the user can hear the result without starting a workout.

import SwiftUI
import AVFoundation
import Combine

// MARK: - SettingsView

struct SettingsView: View {

    @EnvironmentObject private var settings: SettingsStore

    /// Self-contained synthesizer used only to preview the chosen voice.
    @StateObject private var previewer = VoicePreviewer()

    var body: some View {
        NavigationStack {
            Form {
                voiceSection
                exerciseSelectionSection
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Voice Section

    private var voiceSection: some View {
        Section {
            // Voice picker — "System Default" (nil) plus every installed voice
            // for the user's language.
            Picker("Voice", selection: voiceSelection) {
                Text("System Default").tag(String?.none)
                ForEach(availableVoices, id: \.identifier) { voice in
                    Text(voice.name).tag(String?.some(voice.identifier))
                }
            }

            // Pitch — lower is deeper / more authoritative.
            VStack(alignment: .leading) {
                HStack {
                    Text("Pitch")
                    Spacer()
                    Text(String(format: "%.2f", settings.voice.pitch))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $settings.voice.pitch,
                    in: VoicePreferences.pitchRange,
                    step: 0.05
                ) {
                    Text("Pitch")
                } minimumValueLabel: {
                    Image(systemName: "tortoise") // visual anchor: deep
                } maximumValueLabel: {
                    Image(systemName: "hare")
                }
            }

            // Rate — speaking speed.
            VStack(alignment: .leading) {
                HStack {
                    Text("Rate")
                    Spacer()
                    Text(String(format: "%.2f", settings.voice.rate))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $settings.voice.rate,
                    in: VoicePreferences.rateRange,
                    step: 0.05
                )
            }

            Button {
                previewer.speak(sample: "Keep your back straight. Good rep.", using: settings.voice)
            } label: {
                Label("Test voice", systemImage: "speaker.wave.2.fill")
            }
        } header: {
            Text("Coaching Voice")
        } footer: {
            Text("Spoken cues use this voice. Some higher-quality voices must be downloaded in Settings → Accessibility → Spoken Content → Voices.")
        }
    }

    // MARK: - Exercise Selection Section

    private var exerciseSelectionSection: some View {
        Section {
            Picker("Style", selection: $settings.exerciseSelectionStyle) {
                ForEach(ExerciseSelectionStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.inline)
        } header: {
            Text("Exercise Selection")
        } footer: {
            Text("Choose how you pick an exercise: a dedicated screen before the camera, or a compact picker over the live view.")
        }
    }

    // MARK: - Helpers

    /// Binding that maps the optional voice identifier through the settings store.
    private var voiceSelection: Binding<String?> {
        Binding(
            get: { settings.voice.voiceIdentifier },
            set: { settings.voice.voiceIdentifier = $0 }
        )
    }

    /// Installed voices for the user's language, sorted by name. Falls back to all
    /// installed voices if none match (e.g. an unusual locale).
    private var availableVoices: [AVSpeechSynthesisVoice] {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let langPrefix = String(Locale.current.identifier.prefix(2)).lowercased()
        let matching = all.filter { $0.language.lowercased().hasPrefix(langPrefix) }
        return (matching.isEmpty ? all : matching)
            .sorted { $0.name < $1.name }
    }
}

// MARK: - VoicePreviewer

/// A tiny, self-contained speech synthesizer used only to preview voice settings on
/// the Settings screen. Kept separate from AudioCueEngine so previewing never touches
/// the workout cue queue or its rate-limiting state.
final class VoicePreviewer: NSObject, ObservableObject {

    // VoicePreviewer has no @Published state (nothing observes it; @StateObject just
    // keeps it alive across view updates), so the objectWillChange publisher can't be
    // synthesized — declare it explicitly to satisfy ObservableObject.
    let objectWillChange = ObservableObjectPublisher()

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        // Match AudioCueEngine: speech should play even with the phone on silent,
        // ducking any background audio while it speaks.
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: [.duckOthers]
        )
    }

    /// Speaks a sample line using the given preferences, interrupting any current preview.
    func speak(sample text: String, using preferences: VoicePreferences) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = preferences.rate
        utterance.pitchMultiplier = preferences.pitch
        if let id = preferences.voiceIdentifier,
           let chosen = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = chosen
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        }
        synthesizer.speak(utterance)
    }
}
