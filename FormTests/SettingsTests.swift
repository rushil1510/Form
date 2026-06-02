import XCTest
@testable import Form

final class SettingsTests: XCTestCase {

    // MARK: - VoicePreferences

    func testVoicePreferencesClampsPitchAndRateOnInit() {
        let tooHigh = VoicePreferences(voiceIdentifier: nil, pitch: 9.0, rate: 9.0)
        XCTAssertEqual(tooHigh.pitch, VoicePreferences.pitchRange.upperBound)
        XCTAssertEqual(tooHigh.rate, VoicePreferences.rateRange.upperBound)

        let tooLow = VoicePreferences(voiceIdentifier: nil, pitch: -1.0, rate: -1.0)
        XCTAssertEqual(tooLow.pitch, VoicePreferences.pitchRange.lowerBound)
        XCTAssertEqual(tooLow.rate, VoicePreferences.rateRange.lowerBound)
    }

    func testVoicePreferencesDefaultMatchesLegacyVoiceCharacter() {
        // The original hardcoded engine values, now the default preference.
        XCTAssertNil(VoicePreferences.default.voiceIdentifier)
        XCTAssertEqual(VoicePreferences.default.pitch, 0.9, accuracy: 0.0001)
        XCTAssertEqual(VoicePreferences.default.rate, 0.45, accuracy: 0.0001)
    }

    func testVoicePreferencesCodableRoundTripsValues() throws {
        let original = VoicePreferences(voiceIdentifier: "com.apple.voice.test", pitch: 0.8, rate: 0.5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoicePreferences.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testVoicePreferencesReclampsOutOfRangeDecodedData() throws {
        // Simulate on-disk data from a future build / manual edit with bad values.
        let json = Data(#"{"pitch": 5.0, "rate": -2.0}"#.utf8)
        let decoded = try JSONDecoder().decode(VoicePreferences.self, from: json)
        XCTAssertEqual(decoded.pitch, VoicePreferences.pitchRange.upperBound)
        XCTAssertEqual(decoded.rate, VoicePreferences.rateRange.lowerBound)
        XCTAssertNil(decoded.voiceIdentifier)
    }

    // MARK: - SettingsStore

    func testSettingsStorePersistsAcrossInstances() {
        let suite = "SettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        store.voice = VoicePreferences(voiceIdentifier: "com.apple.voice.test", pitch: 0.7, rate: 0.6)
        store.exerciseSelectionStyle = .inlinePicker

        // A fresh store reading the same suite should see the persisted values.
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.voice.voiceIdentifier, "com.apple.voice.test")
        XCTAssertEqual(reloaded.voice.pitch, 0.7, accuracy: 0.0001)
        XCTAssertEqual(reloaded.voice.rate, 0.6, accuracy: 0.0001)
        XCTAssertEqual(reloaded.exerciseSelectionStyle, .inlinePicker)
    }

    func testSettingsStoreFallsBackToDefaultsWhenEmpty() {
        let suite = "SettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.voice, .default)
        XCTAssertEqual(store.exerciseSelectionStyle, .dedicatedScreen)
    }

    func testExerciseSelectionStyleRoundTrips() {
        for style in ExerciseSelectionStyle.allCases {
            XCTAssertEqual(ExerciseSelectionStyle(rawValue: style.rawValue), style)
        }
    }

    // MARK: - ExerciseType positioning metadata

    func testEveryExerciseHasCameraSetupAndSymbol() {
        for exercise in ExerciseType.allCases {
            XCTAssertFalse(exercise.symbolName.isEmpty, "\(exercise) missing symbol")
            XCTAssertFalse(exercise.cameraSetup.placement.isEmpty, "\(exercise) missing placement")
            XCTAssertFalse(exercise.cameraSetup.instruction.isEmpty, "\(exercise) missing instruction")
        }
    }
}
