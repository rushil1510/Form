# Developing Form

This is the first-hour guide for new contributors. It focuses on getting productive without needing to understand every AVFoundation or Vision detail on day one.

## First-Hour Checklist

1. Read `README.md` for the project overview.
2. Read `docs/ARCHITECTURE.md` for the runtime diagrams.
3. Run the logic tests from the repo root.
4. Create a local Xcode project with `XCODE_SETUP.md`.
5. Run on a physical iPhone before debugging camera or pose behavior.

## Requirements

- macOS with Xcode installed at `/Applications/Xcode.app`.
- iPhone running iOS 17 or later for real camera and pose detection.
- Apple ID configured in Xcode for local signing.
- No third-party package setup is required.

## Common Commands

Run every headless logic test:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Run one test suite:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FormAnalyzerTests
```

Inspect the SwiftPM harness:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift package describe
```

If you are running inside a restricted sandbox and SwiftPM cannot write its module cache, use a local cache:

```bash
mkdir -p .build/module-cache
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --disable-sandbox
```

If `swift test` crashes with an `llbuild` symbol error, the CommandLineTools SwiftPM is being used. Keep the `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` prefix.

## Source Layout

```text
Form/Form/App/
  FormApp.swift          App entry point and top-level tabs
  AppState.swift         Shared live-session state

Form/Form/Features/
  Camera/                AVFoundation capture session
  PoseDetection/         Vision body-pose wrapper and JointMap definition
  FormAnalysis/          ExerciseType, FormFeedback, analyzers, geometry helpers
  RepTracking/           RepCounter finite-state machine
  AudioCues/             Spoken feedback queue

Form/Form/UI/
  Workout/               Live camera workout screen and controls
  Sessions/              History list and detail screens
  Components/            Shared drawing components

Form/Form/Models/        Codable session, rep, and score models
Form/Form/Persistence/   SessionStore JSON repository
FormTests/               SwiftPM logic tests
ValidationSupport/       Test-only shims
```

## Development Workflow

### Change Analyzer Rules

1. Edit `Form/Form/Features/FormAnalysis/FormAnalyzer.swift`.
2. Keep rules deterministic and cheap; they can run every frame.
3. Add or update tests in `FormTests/FormAnalyzerTests.swift`.
4. Update `DEMO.md` if a user-visible cue changes.

### Change Rep Counting

1. Edit `Form/Form/Features/RepTracking/RepCounter.swift`.
2. Confirm `ExerciseType.repDetectionJoint` and `ExerciseType.repThresholds` still match the movement.
3. Add or update tests in `FormTests/RepCounterTests.swift`.

### Change Session Data

1. Update models in `Form/Form/Models/`.
2. Update JSON round-trip or persistence tests in `FormTests/AppStateAndPersistenceTests.swift`.
3. Consider migration behavior before changing required `Codable` fields.

### Change Camera, Vision, Audio, or UI

1. Use Xcode and a physical iPhone for runtime verification.
2. Keep hardware-specific code small and move reusable decisions into testable logic.
3. Confirm main-thread updates for anything SwiftUI observes.

## Add a New Exercise

1. Add a case to `ExerciseType`.
2. Add `repDetectionJoint` and `repThresholds` values.
3. Create a new `XxxAnalyzer` conforming to `FormAnalyzing`.
4. Register the analyzer in `makeAnalyzer(for:)`.
5. Add tests for the analyzer and at least one rep-count sequence.
6. Update `README.md`, `DEMO.md`, or `ValidationPlan.md` if the exercise is user-facing.

## Testing Strategy

| Layer | Test Approach |
| --- | --- |
| Geometry helpers | Pure unit tests with fixed points. |
| Analyzers | Build synthetic `JointMap` values and assert feedback. |
| Rep counter | Feed angle sequences and assert completed reps. |
| App state and persistence | Use temp JSON files and deterministic fixtures. |
| Camera and Vision | Verify on device; keep code thin. |
| SwiftUI views | Prefer smoke testing in Xcode unless adding a dedicated UI test target. |

## Common Pitfalls

- The source root is `Form/Form`, not the repo root.
- The committed `Package.swift` is a logic-test harness, not the iOS app build.
- `PoseDetector` defines the real `JointMap`; `ValidationSupport/JointMap.swift` mirrors it only for SwiftPM tests.
- Vision coordinates start bottom-left, but `PoseDetector` flips Y to a top-left origin.
- The front camera is mirrored; left/right checks can feel backwards until you trace the coordinate system.
- `DeadliftAnalyzer` and `BenchAnalyzer` are stubs, so they only support rep counting today.
- Do not add `URLSession` or remote inference to the live analysis path.

## Review Checklist

- New or changed deterministic logic has tests.
- Docs match user-visible cue text and exercise support.
- Session model changes preserve or intentionally migrate existing JSON.
- `@Published` mutations happen on the main thread.
- Camera frames and joint data remain local-only.

