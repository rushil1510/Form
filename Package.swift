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
                "Form/Form/App/FormApp.swift",
                "Form/Form/Features/Camera",
                "Form/Form/Features/PoseDetection",
                "Form/Form/Features/AudioCues",
                "Form/Form/UI",
                "Form/Form/Assets.xcassets",
                "FormTests",
                "docs",
                "README.md",
                "ValidationPlan.md",
                "Availability.md",
                "CLAUDE.md",
                "DEMO.md",
                "XCODE_SETUP.md",
                "Info.plist",
                "Package.swift",
            ],
            sources: [
                "Form/Form/App/AppState.swift",
                "Form/Form/Models",
                "Form/Form/Features/FormAnalysis",
                "Form/Form/Features/RepTracking",
                "Form/Form/Persistence",
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
