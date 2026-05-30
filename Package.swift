// swift-tools-version: 5.9
//
// SwiftPM "logic core" harness — lets you run the pure-logic unit tests from the
// terminal with `swift test`, WITHOUT an Xcode project.
//
// It compiles only the deterministic, hardware-free files (analyzers, rep counter,
// models, persistence, app state) plus a JointMap shim. Camera / Vision / SwiftUI
// files are intentionally excluded — those need a real device and are validated
// on-device, not here. See ValidationPlan.md and CLAUDE.md.
//
//   swift test                                   # run everything
//   swift test --filter RepCounterTests          # one test class
//
// This file does NOT replace the iOS app build; it sits alongside it.

import PackageDescription

let package = Package(
    name: "Form",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "Form",
            path: ".",
            exclude: [
                // Everything not part of the headless logic core.
                "App/FormApp.swift",
                "Features/Camera",
                "Features/PoseDetection",
                "Features/AudioCues",
                "UI",
                "FormTests",
                "README.md",
                "ValidationPlan.md",
                "Availability.md",
                "Info.plist",
                "Package.swift",
            ],
            sources: [
                "App/AppState.swift",
                "Models",
                "Features/FormAnalysis",
                "Features/RepTracking",
                "Persistence",
                "ValidationSupport",
            ]
        ),
        .testTarget(
            name: "FormTests",
            dependencies: ["Form"],
            path: "FormTests"
        ),
    ]
)
