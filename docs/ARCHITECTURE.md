# Architecture

This document is the map for how Form works at runtime. If you are new to the codebase, read `README.md` first, then use this file while navigating the source.

## System Context

```mermaid
flowchart TB
    User["Lifter"] --> App["Form iOS app"]

    subgraph Device["iPhone"]
        Camera["Camera hardware"]
        Vision["Apple Vision pose model"]
        Rules["Local geometry rule engine"]
        Speech["AVSpeechSynthesizer"]
        Storage["Documents directory JSON"]
    end

    Camera --> App
    App --> Vision
    App --> Rules
    App --> Speech
    App --> Storage

    App -. no frame uploads .-> Cloud["Cloud services"]
    Cloud:::blocked

    classDef blocked fill:#331111,stroke:#dd5555,color:#ffffff,stroke-dasharray: 5 5;
```

The app has one firm boundary: video frames and joint coordinates stay on the device. Any future feature that wants remote sync or accounts should keep the live analysis path offline.

## Runtime Pipeline

```mermaid
flowchart LR
    subgraph Hardware["Hardware-facing layer"]
        CameraManager["CameraManager<br/>AVCaptureSession"]
        PoseDetector["PoseDetector<br/>VNDetectHumanBodyPoseRequest"]
    end

    subgraph Logic["Testable logic layer"]
        AnalyzerFactory["makeAnalyzer(for:)"]
        Analyzer["FormAnalyzing<br/>exercise-specific rules"]
        RepCounter["RepCounter<br/>smoothed angle FSM"]
        Models["Session / Rep / FormScore"]
    end

    subgraph AppShell["SwiftUI app shell"]
        WorkoutView["WorkoutView<br/>pipeline orchestration"]
        AppState["AppState<br/>live session state"]
        AudioCueEngine["AudioCueEngine<br/>queued speech"]
        SessionStore["SessionStore<br/>local JSON repository"]
        UI["Camera preview, skeleton,<br/>feedback banner, history"]
    end

    CameraManager -->|CMSampleBuffer| PoseDetector
    PoseDetector -->|JointMap publisher| WorkoutView
    WorkoutView --> AnalyzerFactory
    AnalyzerFactory --> Analyzer
    WorkoutView -->|JointMap| Analyzer
    WorkoutView -->|JointMap + ExerciseType| RepCounter
    Analyzer -->|FormFeedback| AppState
    Analyzer -->|warning/error text| AudioCueEngine
    RepCounter -->|repCompleted| WorkoutView
    WorkoutView -->|Rep| AppState
    AppState -->|completed Session| SessionStore
    SessionStore --> Models
    AppState --> UI
    PoseDetector --> UI
```

## Per-Frame Sequence

```mermaid
sequenceDiagram
    participant Camera as iPhone camera
    participant CM as CameraManager
    participant PD as PoseDetector
    participant WV as WorkoutView
    participant FA as FormAnalyzer
    participant RC as RepCounter
    participant AC as AudioCueEngine
    participant AS as AppState
    participant UI as SwiftUI

    Camera->>CM: capture frame
    Note over CM: sessionQueue
    CM->>PD: cameraManager(_:didOutput:)
    Note over PD: visionQueue
    PD->>PD: run Vision request
    PD->>PD: filter joints and flip Y axis
    PD-->>UI: publish currentJoints
    PD-->>WV: jointPublisher sends JointMap

    alt session is active
        WV->>FA: analyze(joints)
        FA-->>AS: update latestFeedback
        FA-->>AC: enqueue spoken cue when needed
        WV->>RC: update(joints, exercise)
        RC-->>WV: repCompleted
        WV->>AS: recordRep(rep)
        AS-->>UI: re-render HUD and banner
    else no active session
        WV-->>WV: ignore joints for analysis/counting
    end
```

## Component Ownership

```mermaid
graph TD
    FormApp["FormApp"] --> AppState["AppState"]
    FormApp --> SessionStore["SessionStore"]
    FormApp --> SettingsStore["SettingsStore"]
    FormApp --> ContentView["ContentView"]

    ContentView --> WorkoutView["WorkoutView"]
    ContentView --> SessionListView["SessionListView"]
    ContentView --> SettingsView["SettingsView"]

    SettingsView --> SettingsStore
    SettingsView --> VoicePreferences["VoicePreferences"]

    WorkoutView --> CameraManager["CameraManager"]
    WorkoutView --> PoseDetector["PoseDetector"]
    WorkoutView --> RepCounter["RepCounter"]
    WorkoutView --> AudioCueEngine["AudioCueEngine"]
    WorkoutView --> CameraPreviewView["CameraPreviewView"]
    WorkoutView --> SkeletonOverlayView["SkeletonOverlayView"]
    WorkoutView --> WorkoutHUDView["WorkoutHUDView"]
    WorkoutView --> ExerciseSelectionView["ExerciseSelectionView"]
    WorkoutView --> FeedbackBannerView["FeedbackBannerView"]
    WorkoutView --> makeAnalyzer["makeAnalyzer(for:)"]
    WorkoutView --> SettingsStore

    makeAnalyzer --> SquatAnalyzer["SquatAnalyzer"]
    makeAnalyzer --> DeadliftAnalyzer["DeadliftAnalyzer"]
    makeAnalyzer --> BenchAnalyzer["BenchAnalyzer"]
    makeAnalyzer --> LatPulldownAnalyzer["LatPulldownAnalyzer"]
    makeAnalyzer --> DumbbellBenchAnalyzer["DumbbellBenchAnalyzer"]

    SessionListView --> SessionDetailView["SessionDetailView"]
    SessionListView --> SessionStore
    SessionStore --> Session["Session"]
    Session --> Rep["Rep"]
    Session --> FormScore["FormScore"]
```

`WorkoutView` owns the live-session objects with `@StateObject`. `FormApp` owns shared app-level objects (`AppState`, `SessionStore`, `SettingsStore`) with `@StateObject` and injects them through the SwiftUI environment.

## User Preferences

```mermaid
flowchart LR
    SettingsView["SettingsView"] -->|edits| SettingsStore["SettingsStore<br/>@Published, UserDefaults-backed"]
    SettingsStore -->|VoicePreferences| WorkoutView["WorkoutView"]
    WorkoutView -->|apply(_:)| AudioCueEngine["AudioCueEngine"]
    SettingsStore -->|ExerciseSelectionStyle| WorkoutView
    WorkoutView --> Dedicated["ExerciseSelectionView<br/>(dedicated screen)"]
    WorkoutView --> Inline["inline HUD picker"]
```

`SettingsStore` persists two preferences to `UserDefaults` and writes through on every change (via `didSet`):

- **`VoicePreferences`** — a pure, `Codable` value type (`voiceIdentifier`, `pitch`, `rate`) that clamps to `AVSpeechUtterance`'s valid ranges on both init and decode. `WorkoutView` pushes it into `AudioCueEngine` via `apply(_:)` on appear and whenever it changes, so spoken cues pick up the user's chosen voice without restarting a session. The voice is referenced by identifier `String` (not an `AVSpeechSynthesisVoice`) so the model stays on the testable side of the hardware boundary.
- **`ExerciseSelectionStyle`** — an A/B toggle between a dedicated selection screen (`ExerciseSelectionView`, shown over the camera until an exercise is chosen) and an inline picker in the workout HUD. Both variants surface `ExerciseType.cameraSetup` as a positioning tip before the set starts.

The backing `UserDefaults` is injectable so the headless harness can assert persistence against an isolated suite (`SettingsTests`).

## Data Model

```mermaid
classDiagram
    class Session {
        +UUID id
        +Date date
        +ExerciseType exerciseType
        +Rep[] reps
        +String? notes
        +FormScore? formScore
    }

    class Rep {
        +UUID id
        +Date timestamp
        +Int formScore
        +String? dominantError
    }

    class FormScore {
        +UUID id
        +ExerciseType exerciseType
        +Double averageScore
        +Int repCount
        +Date date
        +String grade
        +compute()
    }

    class SessionStore {
        +Session[] sessions
        +save(session:)
        +delete(at:)
        -persist(sessions:)
        -load()
    }

    SessionStore --> Session : stores
    Session *-- Rep : contains
    Session ..> FormScore : computes
```

Sessions are stored as one local JSON file. The app does not currently persist raw video, joint traces, or audio.

## Threading Model

```mermaid
flowchart LR
    SessionQueue["sessionQueue<br/>camera setup + frame callbacks"]
    VisionQueue["visionQueue<br/>Vision inference"]
    MainQueue["main queue<br/>@Published + SwiftUI"]
    AudioQueue["audioQueue<br/>cue dedupe + rate limiting"]
    IOQueue["ioQueue<br/>JSON file I/O"]

    SessionQueue --> VisionQueue
    VisionQueue --> MainQueue
    MainQueue --> AudioQueue
    MainQueue --> IOQueue
    AudioQueue --> MainQueue
    IOQueue --> MainQueue
```

| Queue | Owner | Work |
| --- | --- | --- |
| `sessionQueue` | `CameraManager` | Configure and run `AVCaptureSession`; deliver sample buffers. |
| `visionQueue` | `PoseDetector` | Run body-pose detection one frame at a time. |
| Main queue | SwiftUI and Combine sinks | Mutate `@Published` state and update views. |
| `audioQueue` | `AudioCueEngine` | Deduplicate cues, rate-limit speech, advance the queue. |
| `ioQueue` | `SessionStore` | Read and write session JSON without blocking UI. |

## Extension Points

### Add a New Exercise

```mermaid
flowchart TD
    Case["Add ExerciseType case"] --> Config["Add repDetectionJoint and repThresholds"]
    Config --> Analyzer["Create XxxAnalyzer: FormAnalyzing"]
    Analyzer --> Factory["Register in makeAnalyzer(for:)"]
    Factory --> Tests["Add analyzer and rep-count tests"]
    Tests --> Demo["Update demo or validation notes"]
```

Most new exercises should not require changes to `WorkoutView` or `RepCounter`. If they do, pause and check whether the new logic belongs behind `ExerciseType`, `FormAnalyzing`, or a small helper type instead.

### Improve Form Rules

- Prefer pure geometry helpers and deterministic thresholds first.
- Keep analyzers fast because they run on every detected frame.
- Add temporal state only when a single-frame rule creates false positives.
- Update `ValidationPlan.md` when adding a cue that needs benchmark labels.

## Coordinate Conventions

- `PoseDetector` returns a `JointMap`: `[VNHumanBodyPoseObservation.JointName: CGPoint]`.
- Coordinates are normalized from `0...1`.
- The origin is top-left after `PoseDetector` flips Vision's bottom-left Y axis.
- Front-camera preview is mirrored, so left/right geometry can be surprising.
- Missing joints are normal; analyzers should return `.good` or a neutral result when required joints are absent.

## Testability Boundary

Hardware-facing files are intentionally thin:

- `Form/Form/Features/Camera/CameraManager.swift`
- `Form/Form/Features/PoseDetection/PoseDetector.swift`
- `Form/Form/Features/AudioCues/AudioCueEngine.swift`
- SwiftUI views in `Form/Form/UI/`

Pure logic is covered by the SwiftPM harness:

- `Form/Form/Features/FormAnalysis/FormAnalyzer.swift`
- `Form/Form/Features/RepTracking/RepCounter.swift`
- `Form/Form/App/AppState.swift`
- `Form/Form/Models/`
- `Form/Form/Persistence/`

`ValidationSupport/JointMap.swift` exists only so this pure logic can compile without pulling camera and SwiftUI code into the test target.
