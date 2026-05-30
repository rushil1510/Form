// JointMap.swift — Validation-harness shim
//
// The real JointMap typealias lives in Features/PoseDetection/PoseDetector.swift,
// which also pulls in AVFoundation/camera plumbing that can't compile in a
// headless SwiftPM library target. This shim provides the identical typealias
// so the PURE logic (analyzers, rep counter, models, persistence, app state)
// can be unit-tested from the terminal via `swift test`, with no Xcode project.
//
// Keep this in sync with PoseDetector.swift's definition. It is NOT compiled
// into the iOS app target — only into the `swift test` harness defined in
// Package.swift.

import Foundation
import Vision
import CoreGraphics

typealias JointMap = [VNHumanBodyPoseObservation.JointName: CGPoint]

// `remove(atOffsets:)` (used by SessionStore.delete) is provided by SwiftUI in
// the app build. SwiftUI isn't linked into the headless harness, so we supply an
// equivalent here. Harness-only — never compiled into the iOS app target.
extension RangeReplaceableCollection where Self: MutableCollection, Index == Int {
    mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            remove(at: index)
        }
    }
}
