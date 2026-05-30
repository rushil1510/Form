import Combine
import XCTest
@testable import Form

final class RepCounterTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testCountsOneSquatRepAndPublishesCompletion() {
        let counter = RepCounter()
        counter.configure(for: .squat)

        let completionExpectation = expectation(description: "rep completed")
        var completionCount = 0

        counter.repCompleted
            .sink {
                completionCount += 1
                completionExpectation.fulfill()
            }
            .store(in: &cancellables)

        let sequence =
            Array(repeating: 160.0, count: 5) +
            Array(repeating: 80.0, count: 5) +
            Array(repeating: 160.0, count: 6)

        for angle in sequence {
            counter.update(
                joints: TestFixtures.jointMap(for: .squat, angleDegrees: angle),
                exercise: .squat
            )
        }

        wait(for: [completionExpectation], timeout: 1.0)
        XCTAssertEqual(counter.repCount, 1)
        XCTAssertEqual(completionCount, 1)
    }

    func testDoesNotCountPartialRepThatNeverReturnsAboveHighThreshold() {
        let counter = RepCounter()
        counter.configure(for: .squat)

        let sequence =
            Array(repeating: 160.0, count: 5) +
            Array(repeating: 80.0, count: 5) +
            Array(repeating: 120.0, count: 6)

        for angle in sequence {
            counter.update(
                joints: TestFixtures.jointMap(for: .squat, angleDegrees: angle),
                exercise: .squat
            )
        }

        XCTAssertEqual(counter.repCount, 0)
    }

    func testConfigureUsesExerciseSpecificThresholds() {
        let counter = RepCounter()
        counter.configure(for: .latPulldown)

        let sequence =
            Array(repeating: 160.0, count: 5) +
            Array(repeating: 60.0, count: 5) +
            Array(repeating: 148.0, count: 6)

        for angle in sequence {
            counter.update(
                joints: TestFixtures.jointMap(for: .latPulldown, angleDegrees: angle),
                exercise: .latPulldown
            )
        }

        XCTAssertEqual(counter.repCount, 1)
    }

    func testResetClearsRepCount() {
        let counter = RepCounter()
        counter.configure(for: .squat)

        let sequence =
            Array(repeating: 160.0, count: 5) +
            Array(repeating: 80.0, count: 5) +
            Array(repeating: 160.0, count: 6)

        for angle in sequence {
            counter.update(
                joints: TestFixtures.jointMap(for: .squat, angleDegrees: angle),
                exercise: .squat
            )
        }

        XCTAssertEqual(counter.repCount, 1)
        counter.reset()
        XCTAssertEqual(counter.repCount, 0)
    }

    func testMissingRequiredJointsDoesNotIncrementCount() {
        let counter = RepCounter()
        counter.configure(for: .squat)

        counter.update(joints: [:], exercise: .squat)

        XCTAssertEqual(counter.repCount, 0)
    }
}
