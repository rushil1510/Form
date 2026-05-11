// CameraPreviewView.swift
// Form — UIViewRepresentable: Live Camera Preview
//
// SwiftUI can't directly display an AVCaptureVideoPreviewLayer — that's a
// UIKit (CALayer) concept. UIViewRepresentable is the bridge:
//
//   UIViewRepresentable = "I am a SwiftUI view that wraps a UIKit UIView"
//
// The Representable protocol requires two methods:
//   makeUIView(context:)   — Create and configure the UIView once
//   updateUIView(_:context:) — Called when SwiftUI state changes that might
//                              affect the UIView (we have nothing to update here)
//
// ─── WHY NOT VideoCapture or ARView? ─────────────────────────────────────────
// AVCaptureVideoPreviewLayer is the lowest-level, most performant option for
// displaying a camera feed. It renders directly from the hardware buffer without
// copying to the CPU — this matters at 60fps where every millisecond counts.

import SwiftUI
import AVFoundation

// MARK: - CameraPreviewView

/// A SwiftUI-compatible live camera preview backed by AVCaptureVideoPreviewLayer.
///
/// Usage in SwiftUI:
///   CameraPreviewView(session: cameraManager.session)
///       .ignoresSafeArea()
struct CameraPreviewView: UIViewRepresentable {

    /// The running AVCaptureSession to preview. Must be configured before display.
    let session: AVCaptureSession

    // MARK: - UIViewRepresentable

    /// Creates the UIView once. Called when the view is first added to the hierarchy.
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.session = session
        return view
    }

    /// Called when SwiftUI re-renders with new state. Nothing to update here
    /// because the session reference doesn't change during a workout.
    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // If the session changes (unlikely in our architecture), update it:
        uiView.session = session
    }
}

// MARK: - PreviewUIView

/// The underlying UIView that hosts AVCaptureVideoPreviewLayer.
///
/// We subclass UIView to override layerClass — this tells UIKit to use
/// AVCaptureVideoPreviewLayer as this view's backing CALayer, which allows
/// direct hardware rendering without an extra compositing step.
final class PreviewUIView: UIView {

    // MARK: - Layer Class Override

    /// Tell UIKit which CALayer subclass to use as the backing layer.
    /// This is called ONCE by the UIKit runtime before init() completes.
    ///
    /// By returning AVCaptureVideoPreviewLayer.self, the view's layer IS an
    /// AVCaptureVideoPreviewLayer — no addSublayer() needed.
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    /// Convenience accessor to get the layer as its concrete type.
    private var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer // Safe: layerClass guarantees this type
    }

    // MARK: - Session Binding

    var session: AVCaptureSession? {
        didSet {
            // Connect the layer to the session — this is what makes the live feed appear.
            previewLayer.session = session

            // .resizeAspectFill: fill the view frame, cropping edges if aspect ratios differ.
            // This matches how most camera apps look — no black bars.
            previewLayer.videoGravity = .resizeAspectFill
        }
    }

    // MARK: - Layout

    /// Called when the view's bounds change (rotation, initial layout, etc.).
    /// We must update the preview layer's frame to match.
    override func layoutSubviews() {
        super.layoutSubviews()
        // The preview layer's frame should always match the view's bounds.
        // This handles rotation and dynamic layout changes.
        previewLayer.frame = bounds
    }
}
