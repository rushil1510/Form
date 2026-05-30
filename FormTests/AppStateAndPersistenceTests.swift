import XCTest
@testable import Form

final class AppStateAndPersistenceTests: XCTestCase {
    func testFormFeedbackPresentationMetadata() {
        XCTAssertEqual(FormFeedback.good.message, "Good form! Keep going.")
        XCTAssertEqual(FormFeedback.warning("Brace harder.").colorName, "feedbackWarning")
        XCTAssertEqual(FormFeedback.error("Stop.").message, "🔴 Stop.")
    }

    func testFormScoreComputesAverageAndGrade() {
        let reps = [
            TestFixtures.rep(score: 100),
            TestFixtures.rep(score: 80),
            TestFixtures.rep(score: 60)
        ]

        let score = FormScore.compute(from: reps, exercise: .squat)

        XCTAssertEqual(score?.averageScore, 80)
        XCTAssertEqual(score?.repCount, 3)
        XCTAssertEqual(score?.grade, "B")
    }

    func testSessionComputesAggregateFormScore() {
        let session = TestFixtures.session(
            exercise: .dumbbellBench,
            reps: [
                TestFixtures.rep(score: 90),
                TestFixtures.rep(score: 70)
            ]
        )

        XCTAssertEqual(session.formScore?.exerciseType, .dumbbellBench)
        XCTAssertEqual(session.formScore?.averageScore, 80)
    }

    func testAppStateTracksSessionLifecycle() {
        let appState = AppState()

        appState.startSession(for: .latPulldown)
        XCTAssertTrue(appState.isSessionActive)
        XCTAssertEqual(appState.selectedExercise, .latPulldown)
        XCTAssertEqual(appState.liveRepCount, 0)

        appState.recordRep(TestFixtures.rep(score: 70, error: "Uneven pull"))
        XCTAssertEqual(appState.liveRepCount, 1)
        XCTAssertEqual(appState.currentSession?.reps.count, 1)

        let endedSession = appState.endSession()
        XCTAssertFalse(appState.isSessionActive)
        XCTAssertNil(appState.currentSession)
        XCTAssertEqual(appState.liveRepCount, 0)
        XCTAssertEqual(endedSession?.reps.count, 1)
    }

    func testSessionStoreSaveAndReloadRoundTripsThroughDisk() {
        let url = TestFixtures.temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let saveQueue = DispatchQueue(label: "SessionStoreTests.save")
        let loadQueue = DispatchQueue(label: "SessionStoreTests.load")
        let session = TestFixtures.session(
            exercise: .squat,
            reps: [TestFixtures.rep(score: 100)]
        )

        let store = SessionStore(storageURL: url, ioQueue: saveQueue)
        store.save(session: session)

        waitUntil {
            store.sessions.count == 1 && FileManager.default.fileExists(atPath: url.path)
        }

        let reloadedStore = SessionStore(storageURL: url, ioQueue: loadQueue)

        waitUntil {
            reloadedStore.sessions.count == 1
        }

        XCTAssertEqual(reloadedStore.sessions.first?.exerciseType, .squat)
        XCTAssertEqual(reloadedStore.sessions.first?.reps.count, 1)
        XCTAssertEqual(reloadedStore.sessions.first?.reps.first?.formScore, 100)
    }
}
