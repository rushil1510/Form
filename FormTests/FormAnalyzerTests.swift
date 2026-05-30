import CoreGraphics
import XCTest
@testable import Form

final class FormAnalyzerTests: XCTestCase {
    func testSquatAnalyzerWarnsOnKneeCave() {
        let analyzer = SquatAnalyzer()
        let joints = TestFixtures.jointMap(
            (.leftHip, CGPoint(x: 0.40, y: 0.40)),
            (.leftKnee, CGPoint(x: 0.30, y: 0.60)),
            (.rightHip, CGPoint(x: 0.60, y: 0.40)),
            (.rightKnee, CGPoint(x: 0.55, y: 0.60))
        )

        XCTAssertEqual(
            analyzer.analyze(joints: joints),
            .warning("Keep your knees tracking over your toes.")
        )
    }

    func testSquatAnalyzerWarnsWhenDepthIsTooShallow() {
        let analyzer = SquatAnalyzer()
        let joints = TestFixtures.jointMap(
            (.leftHip, CGPoint(x: 0.40, y: 0.60)),
            (.leftKnee, CGPoint(x: 0.45, y: 0.80)),
            (.rightHip, CGPoint(x: 0.60, y: 0.60)),
            (.rightKnee, CGPoint(x: 0.55, y: 0.80))
        )

        XCTAssertEqual(
            analyzer.analyze(joints: joints),
            .warning("Squat deeper — aim for hips below parallel.")
        )
    }

    func testSquatAnalyzerReturnsGoodForStableStandingPose() {
        let analyzer = SquatAnalyzer()
        let joints = TestFixtures.jointMap(
            (.leftHip, CGPoint(x: 0.40, y: 0.40)),
            (.leftKnee, CGPoint(x: 0.45, y: 0.62)),
            (.rightHip, CGPoint(x: 0.60, y: 0.40)),
            (.rightKnee, CGPoint(x: 0.55, y: 0.62))
        )

        XCTAssertEqual(analyzer.analyze(joints: joints), .good)
    }

    func testLatPulldownAnalyzerWarnsOnShortRangeOfMotion() {
        let analyzer = LatPulldownAnalyzer()

        XCTAssertEqual(
            analyzer.analyze(joints: latPulldownJoints(angleDegrees: 85, shoulderY: 0.40)),
            .warning("Pull the bar all the way to your chest — elbows deeper.")
        )
    }

    func testLatPulldownAnalyzerErrorsOnShoulderShrug() {
        let analyzer = LatPulldownAnalyzer()

        XCTAssertEqual(
            analyzer.analyze(joints: latPulldownJoints(angleDegrees: 70, shoulderY: 0.30)),
            .error("Don't shrug! Pull your shoulders DOWN and back as you pull.")
        )
    }

    func testLatPulldownAnalyzerWarnsOnGripAsymmetry() {
        let analyzer = LatPulldownAnalyzer()

        XCTAssertEqual(
            analyzer.analyze(joints: latPulldownJoints(angleDegrees: 70, shoulderY: 0.40, rightArmYOffset: 0.10)),
            .warning("Keep both arms even — one side is pulling higher.")
        )
    }

    func testLatPulldownAnalyzerWarnsWhenElbowsAreNotFlared() {
        let analyzer = LatPulldownAnalyzer()

        XCTAssertEqual(
            analyzer.analyze(joints: latPulldownJoints(angleDegrees: 70, shoulderY: 0.40, flared: false)),
            .warning("Flare your elbows out to the sides — you'll feel it in your lats.")
        )
    }

    func testDumbbellBenchAnalyzerErrorsOnBilateralAsymmetry() {
        let analyzer = DumbbellBenchAnalyzer()
        let joints = dumbbellBenchJoints(leftAngle: 60, rightAngle: 100)

        XCTAssertEqual(
            analyzer.analyze(joints: joints),
            .error("Left arm is lagging — keep both dumbbells at the same height.")
        )
    }

    func testDumbbellBenchAnalyzerWarnsOnShallowBottomPosition() {
        let analyzer = DumbbellBenchAnalyzer()

        XCTAssertEqual(
            analyzer.analyze(joints: dumbbellBenchJoints(leftAngle: 88, rightAngle: 88)),
            .warning("Lower the dumbbells more — get a full stretch at the bottom.")
        )
    }

    func testDumbbellBenchAnalyzerWarnsOnExcessiveWristDrift() {
        let analyzer = DumbbellBenchAnalyzer()

        XCTAssertEqual(
            analyzer.analyze(joints: dumbbellBenchJoints(leftAngle: 120, rightAngle: 120, forearmLength: 0.16)),
            .warning("Keep your wrists straight — don't let them bend back.")
        )
    }

    func testDumbbellBenchAnalyzerWarnsOnTuckedElbows() {
        let analyzer = DumbbellBenchAnalyzer()

        XCTAssertEqual(
            analyzer.analyze(
                joints: dumbbellBenchJoints(
                    leftAngle: 100,
                    rightAngle: 100,
                    leftShoulder: CGPoint(x: 0.35, y: 0.35),
                    rightShoulder: CGPoint(x: 0.65, y: 0.35),
                    leftElbow: CGPoint(x: 0.20, y: 0.50),
                    rightElbow: CGPoint(x: 0.65, y: 0.50),
                    forearmLength: 0.08
                )
            ),
            .warning("Don't tuck your elbows too tight — about 45° from your torso.")
        )
    }

    func testDumbbellBenchAnalyzerReturnsGoodForControlledSymmetricPress() {
        let analyzer = DumbbellBenchAnalyzer()

        XCTAssertEqual(
            analyzer.analyze(joints: dumbbellBenchJoints(leftAngle: 100, rightAngle: 100, forearmLength: 0.08)),
            .good
        )
    }

    func testFactoryReturnsAnalyzerForRequestedExercise() {
        XCTAssertEqual(makeAnalyzer(for: .squat).exerciseType, .squat)
        XCTAssertEqual(makeAnalyzer(for: .latPulldown).exerciseType, .latPulldown)
        XCTAssertEqual(makeAnalyzer(for: .dumbbellBench).exerciseType, .dumbbellBench)
    }

    private func latPulldownJoints(
        angleDegrees: Double,
        shoulderY: CGFloat,
        rightArmYOffset: CGFloat = 0,
        flared: Bool = true
    ) -> JointMap {
        let leftArm = TestFixtures.arm(
            shoulder: CGPoint(x: 0.35, y: shoulderY),
            elbow: CGPoint(x: 0.35, y: 0.50),
            angleDegrees: angleDegrees,
            side: .left,
            flared: flared
        )
        // Translate the entire right arm down by rightArmYOffset. Moving shoulder,
        // elbow, and wrist together preserves the right elbow angle (so the
        // range-of-motion rule isn't tripped) while making the right hand sit
        // lower than the left — which is what genuine grip asymmetry looks like.
        let rightArm = TestFixtures.arm(
            shoulder: CGPoint(x: 0.65, y: shoulderY + rightArmYOffset),
            elbow: CGPoint(x: 0.65, y: 0.50 + rightArmYOffset),
            angleDegrees: angleDegrees,
            side: .right,
            flared: flared
        )

        return [
            .leftShoulder: leftArm.shoulder,
            .leftElbow: leftArm.elbow,
            .leftWrist: leftArm.wrist,
            .rightShoulder: rightArm.shoulder,
            .rightElbow: rightArm.elbow,
            .rightWrist: rightArm.wrist
        ]
    }

    private func dumbbellBenchJoints(
        leftAngle: Double,
        rightAngle: Double,
        leftShoulder: CGPoint = CGPoint(x: 0.35, y: 0.35),
        rightShoulder: CGPoint = CGPoint(x: 0.65, y: 0.35),
        leftElbow: CGPoint = CGPoint(x: 0.35, y: 0.50),
        rightElbow: CGPoint = CGPoint(x: 0.65, y: 0.50),
        forearmLength: CGFloat = 0.08
    ) -> JointMap {
        let leftArm = TestFixtures.arm(
            shoulder: leftShoulder,
            elbow: leftElbow,
            angleDegrees: leftAngle,
            side: .left,
            forearmLength: forearmLength
        )
        let rightArm = TestFixtures.arm(
            shoulder: rightShoulder,
            elbow: rightElbow,
            angleDegrees: rightAngle,
            side: .right,
            forearmLength: forearmLength
        )

        return [
            .leftShoulder: leftArm.shoulder,
            .leftElbow: leftArm.elbow,
            .leftWrist: leftArm.wrist,
            .rightShoulder: rightArm.shoulder,
            .rightElbow: rightArm.elbow,
            .rightWrist: rightArm.wrist
        ]
    }
}
