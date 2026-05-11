// PoseDetector.swift
// Form — Apple Vision Body Pose Estimation
//
// This file wraps Apple's VNDetectHumanBodyPoseRequest to extract the 2D
// screen positions of body keypoints (joints) from each camera frame.
//
// ─── HOW APPLE'S VISION BODY POSE WORKS ─────────────────────────────────────
// Vision uses a CoreML model trained on thousands of human body images to
// detect 19 named joints (wrist, elbow, shoulder, hip, knee, ankle, etc.)
// in a single pass through a CNN (Convolutional Neural Network).
//
// The output is a VNHumanBodyPoseObservation, which lets you query each joint:
//   let point = try observation.recognizedPoint(.rightWrist)
//   // point.location: CGPoint normalized 0–1, origin at BOTTOM-LEFT
//   // point.confidence: 0.0–1.0 — how sure the model is about this joint
//
// WHY NORMALIZED COORDINATES?
// Vision returns coordinates in "normalized image coordinates" — (0,0) is
// bottom-left, (1,1) is top-right. This is hardware-agnostic: the same values
// work whether the image is 720p or 4K. We flip the Y-axis before drawing
// because UIKit/SwiftUI use top-left origin.
//
// ─── PERFORMANCE ─────────────────────────────────────────────────────────────
// VNDetectHumanBodyPoseRequest runs on the Neural Engine (Apple Silicon) when
// available — typically <5ms per frame on modern iPhones. We still run it on
// a background serial queue to avoid blocking the camera pipeline or the UI.
//
// ─── OFFLINE PRINCIPLE ───────────────────────────────────────────────────────
// All inference happens on-device using Apple's built-in model.
// No image data, no joint coordinates, nothing is transmitted over the network.

import Vision
import AVFoundation
import Combine

// MARK: - Joint Map Type Alias

/// A dictionary mapping each detected joint to its 2D position in VIEW coordinates.
///
/// We use VNHumanBodyPoseObservation.JointName as keys (e.g., .rightWrist)
/// and CGPoint as values (screen space, top-left origin, scaled to view size).
///
/// This type alias makes function signatures more readable throughout the codebase.
typealias JointMap = [VNHumanBodyPoseObservation.JointName: CGPoint]

// MARK: - PoseDetector

/// Receives CMSampleBuffers from CameraManager, runs Apple Vision pose estimation,
/// and publishes the resulting joint positions as a JointMap.
///
/// Downstream consumers: SkeletonOverlayView (drawing) and FormAnalyzer (analysis).
final class PoseDetector: ObservableObject {

    // MARK: - Published Output

    /// The most recently detected joint positions, published on the main thread.
    /// SwiftUI views observing this will re-render whenever a new pose arrives.
    /// nil when no person is detected in the frame.
    @Published private(set) var currentJoints: JointMap? = nil

    // MARK: - Vision Request

    /// VNDetectHumanBodyPoseRequest is a reusable request object.
    ///
    /// WHY reuse instead of creating a new one per frame?
    /// Creating a VNRequest is cheap, but VNImageRequestHandler (created per frame)
    /// does the actual image decoding — reusing the request avoids re-initializing
    /// the model for each frame. Apple recommends this pattern.
    private let bodyPoseRequest = VNDetectHumanBodyPoseRequest()

    // MARK: - Processing Queue

    /// Serial background queue for Vision inference.
    ///
    /// WHY serial (not concurrent)?
    /// Vision's body pose model is not designed for concurrent re-entrant calls.
    /// A serial queue guarantees we process one frame at a time, in order.
    /// With alwaysDiscardsLateVideoFrames = true in CameraManager, we never
    /// build up a backlog — if we're still processing frame N when N+1 arrives,
    /// N+1 is simply dropped.
    private let visionQueue = DispatchQueue(
        label: "com.form.poseDetector.visionQueue",
        qos: .userInitiated
    )

    // MARK: - Combine

    /// A PassthroughSubject is a Combine publisher you can fire manually.
    /// We use it to forward joint maps to other parts of the system (e.g., RepCounter)
    /// without requiring those parts to observe PoseDetector directly via @ObservedObject.
    ///
    /// The type signature reads: "publishes JointMap, never fails."
    let jointPublisher = PassthroughSubject<JointMap, Never>()

    // MARK: - Initializer

    init() {
        // Configure the body pose request.
        // maximumObservationCount = 1 because we expect a single user in frame.
        // Setting this avoids wasted work detecting a second or third person.
        bodyPoseRequest.maximumObservationCount = 1
    }

    // MARK: - Frame Processing

    /// Accepts a CMSampleBuffer from CameraManager and kicks off Vision processing.
    ///
    /// This is called on CameraManager's sessionQueue — NOT the main thread.
    /// We re-dispatch to visionQueue to keep Vision off the camera delivery queue.
    ///
    /// - Parameter sampleBuffer: Raw camera frame. Valid only during this call.
    func process(sampleBuffer: CMSampleBuffer) {
        // CMSampleBufferGetImageBuffer extracts the CVPixelBuffer (the actual pixels)
        // from the CMSampleBuffer wrapper. Vision works with CVPixelBuffers directly.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("[PoseDetector] WARNING: Could not extract pixel buffer from sample buffer")
            return
        }

        // Retain the pixel buffer explicitly before crossing the dispatch boundary.
        // ARC normally handles this, but CMSampleBuffer has unusual memory semantics.
        // Without this, the buffer could be reused by the camera pipeline before
        // Vision finishes reading it.
        let retainedBuffer = pixelBuffer

        visionQueue.async { [weak self] in
            guard let self else { return }
            self.runPoseDetection(on: retainedBuffer)
        }
    }

    // MARK: - Vision Inference

    /// Runs VNDetectHumanBodyPoseRequest on the given pixel buffer synchronously
    /// on the current queue (visionQueue).
    ///
    /// - Parameter pixelBuffer: The raw camera frame pixels.
    private func runPoseDetection(on pixelBuffer: CVPixelBuffer) {
        // VNImageRequestHandler is created per-frame. It handles image decoding
        // and feeds pixels to the Vision model. The orientation tells Vision
        // how the image was captured so it can correct its coordinate system.
        //
        // .right is the correct orientation for front-facing portrait camera on iOS —
        // the sensor is physically rotated 90° and the pixels need to be interpreted
        // accordingly. Getting this wrong causes joints to appear in wrong positions.
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right, // Portrait, front camera
            options: [:]
        )

        do {
            // perform(_:) runs the model synchronously and blocks until done.
            // This is fine because we're on a dedicated background queue.
            try handler.perform([bodyPoseRequest])
        } catch {
            print("[PoseDetector] Vision inference error: \(error.localizedDescription)")
            return
        }

        // results is an array of VNHumanBodyPoseObservation (one per detected person).
        // Since maximumObservationCount = 1, we expect at most one result.
        guard let observation = bodyPoseRequest.results?.first else {
            // No person detected — clear the overlay so skeleton disappears
            DispatchQueue.main.async { self.currentJoints = nil }
            return
        }

        // Convert the raw observation into our clean JointMap type
        let joints = extractJoints(from: observation)

        // Publish results on the main thread (required for @Published + SwiftUI)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentJoints = joints
            self.jointPublisher.send(joints)
        }
    }

    // MARK: - Joint Extraction

    /// Converts a VNHumanBodyPoseObservation into a JointMap.
    ///
    /// We iterate over all recognizable joint names, query each one, filter by
    /// confidence threshold, and flip the Y coordinate to match UIKit's coordinate
    /// system (top-left origin vs Vision's bottom-left origin).
    ///
    /// - Parameter observation: The raw Vision body pose result.
    /// - Returns: A dictionary of joint names to view-space CGPoints.
    private func extractJoints(from observation: VNHumanBodyPoseObservation) -> JointMap {
        var joints = JointMap()

        // VNHumanBodyPoseObservation.JointName.allCases would be ideal but isn't
        // available. Instead, recognizedPoints(forGroupKey:) returns all joints.
        // We use .all to get every joint group at once.
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else {
            return joints
        }

        for (jointName, point) in recognizedPoints {
            // Confidence threshold: skip joints the model is unsure about.
            // 0.3 is a reasonable minimum — lower means more noise, higher means
            // joints disappear too easily when partially occluded.
            guard point.confidence > 0.3 else { continue }

            // Vision's coordinate system:
            //   Origin: bottom-left
            //   X: 0 (left) → 1 (right)
            //   Y: 0 (bottom) → 1 (top)
            //
            // UIKit/SwiftUI coordinate system:
            //   Origin: top-left
            //   X: 0 (left) → 1 (right)
            //   Y: 0 (top) → 1 (bottom)
            //
            // So we flip Y: uiY = 1 - visionY
            let flippedY = 1.0 - point.location.y
            joints[jointName] = CGPoint(x: point.location.x, y: flippedY)
        }

        return joints
    }
}

// MARK: - CameraManagerDelegate Conformance

extension PoseDetector: CameraManagerDelegate {

    /// Called by CameraManager for each incoming camera frame.
    /// We immediately forward the buffer to our Vision processing pipeline.
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        process(sampleBuffer: sampleBuffer)
    }
}
