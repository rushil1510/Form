// VoicePreferences.swift
// Form — User-Configurable Spoken-Cue Voice Settings
//
// The AudioCueEngine speaks coaching cues via AVSpeechSynthesizer. Different users
// want different voices, and a "lower / calmer coach" was a common request — so the
// voice character is no longer hardcoded in the engine. It lives here as a plain,
// Codable value type that the engine reads and the Settings screen writes.
//
// ─── WHY KEEP THIS PURE? ──────────────────────────────────────────────────────
// This type intentionally imports only Foundation — NOT AVFoundation. The voice is
// referenced by its identifier String (e.g. "com.apple.voice.compact.en-US.Samantha"),
// not an AVSpeechSynthesisVoice instance. That keeps the model on the testable side
// of the hardware boundary (see CLAUDE.md): it compiles and round-trips in the
// headless SwiftPM harness, while the engine/UI layer maps the identifier to a real
// voice. A nil identifier means "use the system default for the user's locale".

import Foundation

// MARK: - VoicePreferences

/// Persisted settings controlling how spoken cues sound.
struct VoicePreferences: Codable, Equatable {

    /// AVSpeechSynthesisVoice identifier, or nil to use the locale's default voice.
    var voiceIdentifier: String?

    /// Pitch multiplier. 1.0 = normal; lower = deeper/more authoritative.
    /// AVSpeechUtterance accepts 0.5...2.0 — we clamp to that range.
    var pitch: Float

    /// Speech rate. 0.0 = slowest, 1.0 = fastest (AVSpeechUtterance's normalized
    /// range). Slightly below the ~0.5 default reads clearly over gym noise.
    var rate: Float

    // MARK: - Valid Ranges

    /// AVSpeechUtterance's documented pitch range.
    static let pitchRange: ClosedRange<Float> = 0.5...2.0
    /// AVSpeechUtterance's normalized rate range.
    static let rateRange: ClosedRange<Float> = 0.0...1.0

    // MARK: - Default

    /// The original hardcoded voice character: locale default, slightly low and
    /// slightly slow. Used on first launch and whenever stored data is missing/corrupt.
    static let `default` = VoicePreferences(voiceIdentifier: nil, pitch: 0.9, rate: 0.45)

    // MARK: - Init (clamps on construction)

    init(voiceIdentifier: String?, pitch: Float, rate: Float) {
        self.voiceIdentifier = voiceIdentifier
        self.pitch = pitch.clamped(to: VoicePreferences.pitchRange)
        self.rate = rate.clamped(to: VoicePreferences.rateRange)
    }

    // MARK: - Codable (re-clamp on decode)

    // Decoding goes through the memberwise initializer so out-of-range values that
    // somehow landed on disk (a future build, a manual edit) are clamped back into
    // a range AVSpeechUtterance accepts, rather than being fed to it verbatim.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .voiceIdentifier)
        let p = try container.decode(Float.self, forKey: .pitch)
        let r = try container.decode(Float.self, forKey: .rate)
        self.init(voiceIdentifier: id, pitch: p, rate: r)
    }
}
