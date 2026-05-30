# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Form** is an offline-first iOS app (SwiftUI + AVFoundation + Apple Vision) that coaches gym form in real time. Every camera frame is processed on-device: `VNDetectHumanBodyPoseRequest` extracts joints, a rule engine flags form faults, and spoken cues are emitted. **No network calls, ever** — if you find yourself writing `URLSession`, stop.

## Build & test

There is **no `.xcodeproj` committed**. The app target must be built from Xcode by following `XCODE_SETUP.md`; use ⌘R to run on a device. The Simulator has no useful camera feed, so pose detection only works on a physical iOS 17+ device.

For fast, headless iteration on the **pure logic** (no Xcode, no device), a SwiftPM harness is checked in (`Package.swift` + `ValidationSupport/`). It compiles only the deterministic files and runs `FormTests/` from the terminal:

```bash
# The active CommandLineTools toolchain has a broken SwiftPM — use Xcode's toolchain:
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RepCounterTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RepCounterTests/testResetClearsRepCount
```

If `swift test` errors with a `llbuild` symbol-not-found dyld crash, the `DEVELOPER_DIR` override is missing — the system SwiftPM is broken and only Xcode's works.

The harness is **not** the app build. `Package.swift` deliberately *excludes* `Form/Form/Features/Camera`, `Form/Form/Features/PoseDetection`, `Form/Form/Features/AudioCues`, `Form/Form/UI`, and `Form/Form/App/FormApp.swift` (anything needing UIKit/AVFoundation/SwiftUI hardware), and includes only `Form/Form/Models`, `Form/Form/Features/FormAnalysis`, `Form/Form/Features/RepTracking`, `Form/Form/Persistence`, `Form/Form/App/AppState.swift`, and `ValidationSupport`. `ValidationSupport/JointMap.swift` is a harness-only shim that re-declares the `JointMap` typealias (real one lives in `PoseDetector.swift`) plus a `remove(atOffsets:)` extension (real one comes from SwiftUI). **Keep that shim's `JointMap` in sync with `PoseDetector.swift`.** When you add a new logic file that tests touch, add it to `sources:` in `Package.swift`.

## Architecture

A two-stage, unidirectional pipeline. Data flows down, events flow up; views are functions of state and never mutate it directly.

```
Camera ─CMSampleBuffer→ PoseDetector ─JointMap→ ┬─ SkeletonOverlayView (draw)
 (AVFoundation)          (Vision CNN)            ├─ FormAnalyzer  → FormFeedback → AppState → banner
                                                 ├─ AudioCueEngine (dedup + rate-limit TTS)
                                                 └─ RepCounter (FSM) → repCompleted → AppState.recordRep
                                                                                         │
                                                                  SessionStore (JSON) ◀──┘ (on session end)
```

**The hardware boundary is the key design line.** `PoseDetector`/`CameraManager` are thin and hard to test (need a device); all decision logic lives in plain value types that take a `JointMap` (`[VNHumanBodyPoseObservation.JointName: CGPoint]`, normalized 0–1, **top-left origin** — `PoseDetector` flips Vision's bottom-left Y) and are trivially testable. When adding logic, keep it on the testable side of this line.

**`ExerciseType` is the central config hub** (`Form/Form/Features/FormAnalysis/FormAnalyzer.swift`). Each case carries its own `repDetectionJoint` (which 3 joints define the tracked angle) and `repThresholds` (low/high angle gates). Adding an exercise = add a case here, add a `FormAnalyzing` struct, and register it in `makeAnalyzer(for:)` — `WorkoutView` and `RepCounter` need no changes (Strategy + Factory).

**`FormAnalyzer` is per-frame and stateless-ish; `RepCounter` is temporal.** Analyzers return `.good / .warning(msg) / .error(msg)` from a single frame's joints (pure trig vs. thresholds — no ML). `RepCounter` is a 3-state FSM (idle → descending → ascending → rep) over a smoothed angle time-series; `configure(for:)` swaps thresholds per exercise and resets. Analyzer **status varies**: `SquatAnalyzer`, `LatPulldownAnalyzer`, `DumbbellBenchAnalyzer` have real rules; `DeadliftAnalyzer` and `BenchAnalyzer` are stubs that always return `.good` (so for those, only rep counting is meaningful today).

**Threading contract:** one serial background queue per subsystem (`sessionQueue`, `visionQueue`, `ioQueue`, `audioQueue`); all `@Published` mutations and UI updates hop to `DispatchQueue.main`. `SessionStore.save` does an optimistic main-thread array update, then persists on `ioQueue`. `SessionStore`/`AppState`/`RepCounter`/`PoseDetector` are `ObservableObject`s observed by SwiftUI views.

Coordinate convention is a recurring footgun: front camera is mirrored, Y is top-left origin (flipped from Vision). "Knee outside hip" / "shoulder shrug" rules encode this mirroring — re-read the comments before touching analyzer geometry.

## Validating accuracy

See `ValidationPlan.md` for the full three-layer plan (pure logic → offline replay → on-device smoke). The pure-logic layer is what `swift test` covers. For replay-based accuracy metrics (rep-count MAE, cue precision/recall/F1) against public datasets, the lever is that all logic operates on `JointMap` traces — so you can replay precomputed pose keypoints without running Vision or downloading raw video. Apple Vision itself cannot run off Apple platforms (e.g. Kaggle/Linux); validate the *rules*, not Vision, off-device.
