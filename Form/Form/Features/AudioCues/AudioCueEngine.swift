// AudioCueEngine.swift
// Form — Queue-Based Audio Feedback via AVSpeechSynthesizer
//
// ─── WHY AUDIO FEEDBACK? ─────────────────────────────────────────────────────
// During a heavy lift, the user's eyes are either closed or focused on form —
// not reading a screen banner. Spoken cues reach the user regardless of where
// they're looking, making audio the highest-value feedback channel for real-time
// coaching.
//
// ─── WHY QUEUEING? ────────────────────────────────────────────────────────────
// FormAnalyzer runs at up to 30fps. Without queueing, if the analyzer fires
// "Keep your knees out" 10 times in 333ms, AVSpeechSynthesizer would be
// interrupted and restarted 10 times — producing a stuttering, unusable experience.
//
// Our queue enforces two rules:
//   1. DEDUPLICATION: If the same cue is already queued or speaking, skip it.
//   2. RATE LIMITING: After speaking a cue, enforce a minimum gap before the next.
//
// This gives the user time to RESPOND to a cue before the next one fires.
// Real-time feedback UX rule: a cue is only helpful if the user has time to act on it.
//
// ─── IMPLEMENTATION CHOICE ───────────────────────────────────────────────────
// AVSpeechSynthesizer is Apple's built-in TTS (Text-To-Speech) engine.
// It supports iOS 7+ and runs entirely on-device — no network, no subscription.
// For a v1, it's the correct choice. Future versions could use a custom voice
// model for a more "personal trainer" feel, but AVSpeechSynthesizer is adequate
// for coaching cues that are short and utilitarian ("Knees out!").

import AVFoundation
import Combine

// MARK: - AudioCueEngine

/// Queues and delivers spoken form feedback cues without overlapping or spamming.
final class AudioCueEngine: NSObject, ObservableObject {

    // MARK: - Private

    /// Apple's built-in text-to-speech engine.
    /// One synthesizer per app is the recommended pattern — creating multiple
    /// instances causes audio session conflicts.
    private let synthesizer = AVSpeechSynthesizer()

    /// Serial queue for thread-safe access to the cue queue and dedup state.
    /// Audio decisions must be serialized to prevent race conditions between
    /// the FormAnalyzer (running fast) and the synthesizer delegate callbacks.
    private let audioQueue = DispatchQueue(label: "com.form.audioCueEngine", qos: .userInitiated)

    /// FIFO queue of pending spoken cues.
    /// We use an array as a simple queue (append to back, remove from front).
    private var cueQueue: [String] = []

    /// The cue currently being spoken (or nil if silent).
    private var currentCue: String? = nil

    /// Timestamp of when the last cue finished speaking.
    /// Used to enforce a minimum gap between cues.
    private var lastCueFinishedAt: Date = .distantPast

    /// Minimum seconds between cues. Long enough for the user to hear and react.
    /// 3 seconds is a good starting point — too short causes audio fatigue.
    private let minimumCueGapSeconds: TimeInterval = 3.0

    // MARK: - Initializer

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    // MARK: - Audio Session

    /// Configures AVAudioSession so speech plays even when the phone is on silent.
    ///
    /// WHY .playback category?
    /// .playback continues audio even in silent/Do Not Disturb mode.
    /// For gym coaching, silent mode should NOT silence coaching cues —
    /// the user has muted notification sounds, not intentional audio feedback.
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio, // Optimized for speech; ducks background music
                options: [.duckOthers] // Lower music volume while speaking
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[AudioCueEngine] WARNING: Could not configure audio session: \(error)")
        }
    }

    // MARK: - Public Interface

    /// Requests that a cue be spoken. Will be ignored if:
    ///   - The same cue is already queued or speaking (deduplication)
    ///   - The queue already has 2+ pending cues (backpressure)
    ///
    /// - Parameter text: The coaching cue to speak. Keep it short (< 6 words)
    ///   so it finishes speaking quickly and doesn't block subsequent cues.
    func enqueue(cue text: String) {
        audioQueue.async { [weak self] in
            guard let self else { return }

            // DEDUPLICATION: Don't repeat the same message back-to-back
            guard text != self.currentCue, !self.cueQueue.contains(text) else { return }

            // BACKPRESSURE: Cap the queue to prevent stale advice
            // If we already have 2 cues waiting, the user can't keep up anyway
            guard self.cueQueue.count < 2 else { return }

            self.cueQueue.append(text)
            self.speakNextIfReady()
        }
    }

    /// Immediately stops all speech and clears the queue.
    /// Call this when a session ends so no coaching cue fires after the user stops.
    func stopAll() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.cueQueue.removeAll()
            self.currentCue = nil
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }
        }
    }

    // MARK: - Private: Playback Logic

    private func speakNextIfReady() {
        // Already speaking? Wait for the delegate callback to advance the queue.
        guard !synthesizer.isSpeaking, currentCue == nil else { return }

        // Enforce minimum gap between cues
        let elapsed = Date().timeIntervalSince(lastCueFinishedAt)
        guard elapsed >= minimumCueGapSeconds else {
            // Schedule a retry after the gap expires
            let delay = minimumCueGapSeconds - elapsed
            audioQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.speakNextIfReady()
            }
            return
        }

        guard let nextCue = cueQueue.first else { return }
        cueQueue.removeFirst()
        currentCue = nextCue

        // AVSpeechUtterance wraps a string with voice/rate/pitch settings.
        let utterance = AVSpeechUtterance(string: nextCue)

        // Rate: 0.0 (very slow) to 1.0 (very fast). Default ~0.5.
        // Slightly below default so instructions are clear over gym ambient noise.
        utterance.rate = 0.45

        // Voice: use the system default for the user's locale.
        // In a future version, allow the user to select a voice.
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)

        // pitchMultiplier: 1.0 = normal. Slightly lower feels more authoritative.
        utterance.pitchMultiplier = 0.9

        // speakUtterance must be called on the main thread per Apple docs
        DispatchQueue.main.async {
            self.synthesizer.speak(utterance)
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AudioCueEngine: AVSpeechSynthesizerDelegate {

    /// Called when the synthesizer finishes speaking an utterance.
    /// This is our signal to advance the queue.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.currentCue = nil
            self.lastCueFinishedAt = Date()
            self.speakNextIfReady()
        }
    }

    /// Called if speech is cancelled (e.g., stopAll() was called).
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        audioQueue.async { [weak self] in
            self?.currentCue = nil
        }
    }
}
