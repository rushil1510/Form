// CameraManager.swift
// Form — AVFoundation Camera Pipeline
//
// This file owns the entire camera capture stack. It:
//   1. Requests camera permission from the user
//   2. Configures an AVCaptureSession with the front or back camera
//   3. Adds a video output that delivers raw CMSampleBuffers
//   4. Forwards those buffers to a delegate for pose detection
//
// ─── WHY AVFoundation? ───────────────────────────────────────────────────────
// AVFoundation is Apple's low-level media framework. It gives us per-frame
// access to raw pixel data via CMSampleBuffer, which is exactly what the
// Vision framework needs to run body pose detection.
//
// A simpler alternative would be PhotosUI or a SwiftUI camera sheet — but
// those give you still photos or recorded videos, not live frame-by-frame access.
// AVFoundation is the only public API for real-time computer vision on iOS.
//
// ─── THREAD MODEL ────────────────────────────────────────────────────────────
// AVCaptureSession is NOT thread-safe. The Apple docs say:
//   "Do not call startRunning() on the main thread — it blocks."
// So we configure and run the session on a dedicated background serial queue.
// UI updates (published properties) must hop back to the main thread.
//
// ─── OFFLINE PRINCIPLE ───────────────────────────────────────────────────────
// Raw camera frames are NEVER written to disk or sent over a network.
// The CMSampleBuffer flows: Camera → PoseDetector → FormAnalyzer → UI.
// After the chain processes each frame, the buffer is released by ARC (automatic
// reference counting) — it never persists beyond that frame's processing cycle.

import AVFoundation
import Combine

// MARK: - Delegate Protocol

/// Any object that wants to receive raw camera frames must conform to this protocol.
///
/// WHY a protocol instead of a closure or Combine publisher?
/// Closures would work, but protocols make the relationship explicit and testable.
/// We can swap in a mock delegate in unit tests without touching CameraManager.
/// Combine publishers are great for UI state, but for high-frequency CMSampleBuffer
/// delivery (60fps = 60 calls/second), a direct delegate call is lower overhead.
protocol CameraManagerDelegate: AnyObject {
    /// Called on the sessionQueue (background thread!) for every captured video frame.
    /// The receiver (PoseDetector) should do its Vision processing here and NOT
    /// attempt to update UI directly — UI updates require DispatchQueue.main.async.
    ///
    /// - Parameter sampleBuffer: The raw camera frame as a Core Media sample buffer.
    ///   This contains both the pixel data and timing metadata (presentation timestamp).
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer)
}

// MARK: - CameraManager

/// Manages the AVCaptureSession lifecycle: permission, configuration, start, stop.
///
/// This is a class (reference type) rather than a struct because:
///   - It holds AVFoundation objects that are inherently reference types
///   - It needs to conform to AVCaptureVideoDataOutputSampleBufferDelegate,
///     which requires NSObject (and therefore a class)
final class CameraManager: NSObject, ObservableObject {

    // MARK: - Public State

    /// Whether the camera is actively running. Observed by CameraPreviewView.
    @Published private(set) var isRunning: Bool = false

    /// Reflects the current permission state so the UI can show appropriate prompts.
    @Published private(set) var permissionGranted: Bool = false

    /// Set this before calling startSession(). Receives every CMSampleBuffer.
    weak var delegate: CameraManagerDelegate?

    // MARK: - AVFoundation Objects

    /// AVCaptureSession is the core coordinator — it connects inputs (camera)
    /// to outputs (video data). Think of it as a pipeline: camera → session → output.
    let session = AVCaptureSession()

    /// All AVCaptureSession configuration must happen on this queue to avoid
    /// blocking the main thread. We also deliver sample buffers on this queue
    /// so frame processing is sequential (no dropped frames from queue backup).
    private let sessionQueue = DispatchQueue(
        label: "com.form.cameraManager.sessionQueue",
        qos: .userInitiated // Slightly elevated priority; camera needs consistent throughput
    )

    // MARK: - Initializer

    override init() {
        super.init()
        checkPermission()
    }

    // MARK: - Permission

    /// Checks the current camera authorization status and requests it if not determined.
    ///
    /// iOS requires explicit user consent before any app can use the camera.
    /// The permission dialog text comes from NSCameraUsageDescription in Info.plist.
    ///
    /// Authorization states:
    ///   .notDetermined — First time the app runs; we must request access
    ///   .authorized    — User said yes; proceed
    ///   .denied        — User said no; we must send them to Settings
    ///   .restricted    — Parental controls or MDM; can't request
    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            configureSession()

        case .notDetermined:
            // requestAccess shows the system permission dialog.
            // The completion handler is called on an arbitrary thread, so we
            // hop to sessionQueue for consistent thread model.
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                }
                if granted {
                    self?.configureSession()
                }
            }

        case .denied, .restricted:
            // Can't show dialog again. UI should show a "Go to Settings" button.
            DispatchQueue.main.async { self.permissionGranted = false }

        @unknown default:
            // Future-proof: Apple may add new cases in later OS versions.
            break
        }
    }

    // MARK: - Session Configuration

    /// Configures the AVCaptureSession with camera input and video data output.
    ///
    /// This runs on sessionQueue to avoid blocking the main thread.
    /// Configuration must happen between beginConfiguration() / commitConfiguration()
    /// so that changes are applied atomically (all at once, not one by one).
    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            // Atomic configuration block — no partial states visible to other threads
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() } // Always commit, even if we return early

            // ── Preset ──────────────────────────────────────────────────────
            // .hd1280x720 balances resolution (enough for body pose) vs frame rate.
            // 4K would be overkill and would stress the Vision pipeline unnecessarily.
            self.session.sessionPreset = .hd1280x720

            // ── Camera Input ─────────────────────────────────────────────────
            // We prefer the FRONT camera so users can see their own form.
            // Fall back to back camera if front is unavailable (some iPad configs).
            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .front                       // Face the user
            ) ?? AVCaptureDevice.default(for: .video) else {
                print("[CameraManager] ERROR: No camera available on this device")
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                // Always check canAddInput before adding — simulator doesn't have cameras
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
            } catch {
                print("[CameraManager] ERROR creating device input: \(error)")
                return
            }

            // ── Video Data Output ─────────────────────────────────────────────
            // AVCaptureVideoDataOutput is the bridge between AVFoundation and Vision.
            // It fires captureOutput(_:didOutput:from:) for every frame.
            let videoOutput = AVCaptureVideoDataOutput()

            // kCVPixelFormatType_420YpCbCr8BiPlanarFullRange is Vision's preferred
            // pixel format. YpCbCr is a color space efficient for video compression;
            // Vision reads it directly without an extra color conversion step.
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]

            // alwaysDiscardsLateVideoFrames: if the delegate is still processing
            // the previous frame when a new one arrives, drop the new one.
            // This prevents a growing queue of unprocessed frames that would
            // add latency — real-time feedback must be low-latency above all else.
            videoOutput.alwaysDiscardsLateVideoFrames = true

            // Deliver frames on sessionQueue (same queue we're configuring on).
            // This keeps all AVFoundation work on one thread.
            videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)

            if self.session.canAddOutput(videoOutput) {
                self.session.addOutput(videoOutput)
            }

            // Ensure the video connection is in portrait orientation to match
            // how users hold their phone while working out.
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90 // Portrait
                }
                // Mirror the front camera so it feels like looking in a mirror —
                // the natural gym experience users expect.
                connection.isVideoMirrored = true
            }
        }
    }

    // MARK: - Session Control

    /// Starts the capture session. Call this when WorkoutView appears.
    /// Safe to call multiple times — AVCaptureSession is idempotent if already running.
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    /// Stops the capture session. Call this when WorkoutView disappears
    /// or the user ends a workout. Stopping saves battery and camera resources.
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Called by AVFoundation on sessionQueue for every captured video frame.
    ///
    /// - Parameter output: The output that produced the buffer (we only have one).
    /// - Parameter sampleBuffer: The frame data wrapped in a Core Media container.
    ///   This buffer is valid only during this function call — if you need to hold
    ///   it longer, call CMSampleBufferCreateCopy(). PoseDetector processes it
    ///   synchronously within this call, so no copy is needed.
    /// - Parameter connection: The AVCaptureConnection that produced this frame.
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Forward the raw buffer to whoever is listening (PoseDetector).
        // We're already on sessionQueue here — delegate must not block for long
        // or we'll back up the camera pipeline and drop frames.
        delegate?.cameraManager(self, didOutput: sampleBuffer)
    }
}
