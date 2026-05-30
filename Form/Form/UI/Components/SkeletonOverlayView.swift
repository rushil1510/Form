// SkeletonOverlayView.swift
// Form — SwiftUI Canvas Skeleton Drawing
//
// This view draws a wireframe "stick figure" skeleton over the live camera feed
// by connecting pairs of detected joints with lines and drawing circles at joints.
//
// ─── WHY SwiftUI Canvas? ─────────────────────────────────────────────────────
// Canvas is SwiftUI's immediate-mode drawing API, introduced in iOS 15.
// Unlike regular SwiftUI views (which have state and identity), Canvas draws
// directly into a graphics context — similar to Core Graphics / HTML Canvas.
//
// For skeleton drawing, Canvas is correct because:
//   1. The skeleton has NO independent state — it's purely a function of jointMap
//   2. It needs to redraw every frame (30–60fps) without creating/destroying views
//   3. Path drawing in Core Graphics is GPU-accelerated
//
// Alternative: using Shape views or Path in a ZStack. This works but creates
// SwiftUI view identity overhead for each line segment — less efficient at 60fps.
//
// ─── COORDINATE SYSTEM ───────────────────────────────────────────────────────
// PoseDetector outputs joint positions in NORMALIZED coordinates (0–1).
// Canvas receives a CGRect with the actual pixel size of the view.
// We scale: screenX = normalizedX * width, screenY = normalizedY * height
//
// ─── JOINT CONNECTION MAP ────────────────────────────────────────────────────
// The human body skeleton connects in the following chains:
//
//   HEAD / NECK
//     nose ─── neck (estimated midpoint of shoulders)
//
//   LEFT ARM
//     leftShoulder ─── leftElbow ─── leftWrist
//
//   RIGHT ARM
//     rightShoulder ─── rightElbow ─── rightWrist
//
//   SHOULDERS (crossbar)
//     leftShoulder ─── rightShoulder
//
//   TORSO
//     (midpoint of shoulders) ─── (midpoint of hips)
//
//   LEFT LEG
//     leftHip ─── leftKnee ─── leftAnkle
//
//   RIGHT LEG
//     rightHip ─── rightKnee ─── rightAnkle
//
//   HIPS (crossbar)
//     leftHip ─── rightHip

import SwiftUI
import Vision // For VNHumanBodyPoseObservation.JointName

// MARK: - SkeletonOverlayView

/// Draws a 2D skeleton wireframe over the camera preview.
/// Transparent background — designed to be layered on top of CameraPreviewView.
struct SkeletonOverlayView: View {

    /// The current joint positions from PoseDetector.
    /// When nil, the overlay draws nothing (no person detected).
    let joints: JointMap?

    /// The color of skeleton lines. Orange matches our app accent color.
    var lineColor: Color = .orange

    /// The color of joint dots. White for visibility against the line color.
    var dotColor: Color = .white

    var body: some View {
        Canvas { context, size in
            // If no joints detected, draw nothing
            guard let joints else { return }

            // Draw bone connections first (behind joint dots)
            drawBones(context: context, size: size, joints: joints)

            // Draw joint dots on top
            drawJointDots(context: context, size: size, joints: joints)
        }
        // The canvas itself is transparent — camera feed shows through
        .background(Color.clear)
    }

    // MARK: - Bone Drawing

    /// Draws all bone lines between connected joint pairs.
    private func drawBones(context: GraphicsContext, size: CGSize, joints: JointMap) {
        // Define which joint pairs should be connected by a line.
        // Each tuple is (start joint, end joint).
        let bonePairs: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
            // ── Left Arm ──────────────────────────────────────────────────
            (.leftShoulder,  .leftElbow),
            (.leftElbow,     .leftWrist),

            // ── Right Arm ─────────────────────────────────────────────────
            (.rightShoulder, .rightElbow),
            (.rightElbow,    .rightWrist),

            // ── Shoulder Crossbar ─────────────────────────────────────────
            (.leftShoulder,  .rightShoulder),

            // ── Left Leg ──────────────────────────────────────────────────
            (.leftHip,       .leftKnee),
            (.leftKnee,      .leftAnkle),

            // ── Right Leg ─────────────────────────────────────────────────
            (.rightHip,      .rightKnee),
            (.rightKnee,     .rightAnkle),

            // ── Hip Crossbar ──────────────────────────────────────────────
            (.leftHip,       .rightHip),

            // ── Torso (left side) ─────────────────────────────────────────
            (.leftShoulder,  .leftHip),

            // ── Torso (right side) ────────────────────────────────────────
            (.rightShoulder, .rightHip),

            // ── Neck to Nose ──────────────────────────────────────────────
            (.leftShoulder,  .neck),   // Approximate neck as left shoulder
            (.neck,          .nose),
        ]

        for (startJoint, endJoint) in bonePairs {
            // Both joints must be detected to draw a bone between them
            guard
                let startNorm = joints[startJoint],
                let endNorm   = joints[endJoint]
            else { continue }

            // Convert normalized coords to screen coords
            let startPoint = CGPoint(x: startNorm.x * size.width, y: startNorm.y * size.height)
            let endPoint   = CGPoint(x: endNorm.x * size.width,   y: endNorm.y * size.height)

            // Build a Path for this bone segment
            var path = Path()
            path.move(to: startPoint)
            path.addLine(to: endPoint)

            // Stroke the bone line
            context.stroke(
                path,
                with: .color(lineColor.opacity(0.85)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
        }
    }

    // MARK: - Joint Dot Drawing

    /// Draws a filled circle at each detected joint position.
    private func drawJointDots(context: GraphicsContext, size: CGSize, joints: JointMap) {
        let dotRadius: CGFloat = 5

        for (_, normalizedPoint) in joints {
            let screenPoint = CGPoint(
                x: normalizedPoint.x * size.width,
                y: normalizedPoint.y * size.height
            )

            // Create a circle path centered on the joint
            let dotRect = CGRect(
                x: screenPoint.x - dotRadius,
                y: screenPoint.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )

            let dotPath = Path(ellipseIn: dotRect)
            context.fill(dotPath, with: .color(dotColor))
        }
    }

    // MARK: - Coordinate Conversion Helper

    /// Converts a normalized joint position (0–1) to a screen-space CGPoint.
    private func toScreen(_ normalizedPoint: CGPoint, in size: CGSize) -> CGPoint {
        return CGPoint(
            x: normalizedPoint.x * size.width,
            y: normalizedPoint.y * size.height
        )
    }
}
