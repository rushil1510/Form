import CoreGraphics
import Foundation
import Vision
import XCTest
@testable import Form

enum TestFixtures {
    enum ArmSide {
        case left
        case right
    }

    static func jointMap(_ entries: (VNHumanBodyPoseObservation.JointName, CGPoint)...) -> JointMap {
        Dictionary(uniqueKeysWithValues: entries)
    }

    static func jointMap(
        for exercise: ExerciseType,
        angleDegrees: Double,
        center: CGPoint = CGPoint(x: 0.5, y: 0.5),
        radius: CGFloat = 0.2
    ) -> JointMap {
        let (jointA, jointB, jointC) = exercise.repDetectionJoint
        let radians = CGFloat(angleDegrees) * .pi / 180

        let pointA = CGPoint(x: center.x + radius, y: center.y)
        let pointC = CGPoint(
            x: center.x + radius * cos(radians),
            y: center.y + radius * sin(radians)
        )

        return [
            jointA: pointA,
            jointB: center,
            jointC: pointC
        ]
    }

    static func arm(
        shoulder: CGPoint,
        elbow: CGPoint,
        angleDegrees: Double,
        side: ArmSide,
        forearmLength: CGFloat = 0.16,
        flared: Bool = true
    ) -> (shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint) {
        let baseAngle = atan2(shoulder.y - elbow.y, shoulder.x - elbow.x)
        let sideDirection: CGFloat = side == .left ? 1 : -1
        let flareDirection: CGFloat = flared ? 1 : -1
        let wristAngle = baseAngle + sideDirection * flareDirection * CGFloat(angleDegrees) * .pi / 180

        let wrist = CGPoint(
            x: elbow.x + forearmLength * cos(wristAngle),
            y: elbow.y + forearmLength * sin(wristAngle)
        )

        return (shoulder, elbow, wrist)
    }

    static func rep(
        score: Int = 100,
        error: String? = nil,
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Rep {
        Rep(timestamp: timestamp, formScore: score, dominantError: error)
    }

    static func session(
        exercise: ExerciseType = .squat,
        reps: [Rep] = [rep()],
        date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Session {
        Session(
            id: UUID(),
            date: date,
            exerciseType: exercise,
            reps: reps,
            notes: nil
        )
    }

    static func temporaryFileURL(name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
    }
}

extension XCTestCase {
    func waitUntil(
        timeout: TimeInterval = 1.0,
        pollInterval: TimeInterval = 0.01,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }

        XCTAssertTrue(condition(), "Condition not met before timeout", file: file, line: line)
    }
}
