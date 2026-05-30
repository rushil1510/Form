# Validation Plan

## What to prove

Validate the app in three layers:

1. Pure logic
   Geometry, rep counting, analyzer rules, state transitions, persistence.
2. Offline replay
   Run recorded clips or joint traces through the app and compare counts/cues to labels.
3. On-device smoke tests
   Verify camera permission, live pose stability, cue timing, and persistence on real hardware.

## What this repo can validate today

- `SquatAnalyzer`, `LatPulldownAnalyzer`, and `DumbbellBenchAnalyzer` have concrete rules and are worth benchmarking now.
- `DeadliftAnalyzer` and `BenchAnalyzer` are still stubs, so today you can only validate rep counting and app plumbing for those exercises, not real form coaching accuracy.
- `RepCounter` now uses per-exercise thresholds instead of the squat defaults for every movement.

## Unit tests to keep

- `GeometryHelpers.angle`
  90 degree, 180 degree, and degenerate-point cases.
- `RepCounter`
  Full rep detected, partial rep ignored, reset behavior, missing-joint no-op, per-exercise threshold coverage.
- `SquatAnalyzer`
  Knee cave warning, shallow-depth warning, neutral standing pose.
- `LatPulldownAnalyzer`
  Short range-of-motion warning, shrug error, grip asymmetry warning, elbow-flare warning.
- `DumbbellBenchAnalyzer`
  bilateral asymmetry error, shallow bottom warning, wrist-drift warning, tucked-elbow warning, clean rep.
- `AppState`
  start, record rep, end session.
- `SessionStore`
  save to disk and load back from a temp file.

## Acceptance metrics

- Rep counting
  Exact-count accuracy and mean absolute error per clip.
- Form cueing
  Precision, recall, and F1 per cue type.
- Timing
  Median delay from fault onset to spoken/text cue.
- Stability
  False-cue rate per minute on good-form clips.
- Pose availability
  Percentage of frames where required joints are present.

## Public benchmark candidates

### 0. Low-friction first pass: Gym Workout/Exercises Video

- Site: https://www.kaggle.com/datasets/philosopher0808/gym-workoutexercises-video
- Best use:
  quick proof-of-concept testing that Apple Vision can read joints from saved workout videos.
- Why it fits:
  it is easy to get, already split into short `.mp4` clips, and the folder names act as exercise labels.
- Caveat:
  it is primarily a video-classification dataset, not a form-correction benchmark. It does not give you per-rep correctness labels, cue-timing labels, or consistent camera setup.

### 1. Fit3D

- Site: https://fit3d.imar.ro/
- Best use:
  exercise coverage, repetition segmentation, multi-view robustness, and pose replay.
- Why it fits:
  the dataset site says it contains 611 multi-view sequences, over 47 exercises, 4 views, 50 fps, and repetition segmentations.
- Caveat:
  access requires an account, and you will still need your own labels for your exact warning strings.

### 2. Fitness-AQA

- Repo: https://github.com/ParitoshParmar/Fitness-AQA
- Best use:
  squat-form proof of concept.
- Why it fits:
  the official repo says the dataset targets fine-grained exercise action quality assessment and includes BackSquat, OverheadPress, and BarbellRow.
- Caveat:
  great for squat scoring, but not a direct match for lat pulldown or dumbbell bench.

### 3. QEVD Fit-Coach / Fit-Coach-Benchmark

- Site: https://www.qualcomm.com/developer/software/qevd-dataset
- Best use:
  end-to-end cueing and feedback timing.
- Why it fits:
  Qualcomm says the benchmark includes workout videos annotated with live coaching feedback and corrective feedback.
- Caveat:
  it is broader than your current exercise list, so use it mainly for feedback-style validation rather than one-to-one exercise coverage.

### 4. MM-Fit

- Site: https://mmfit.github.io/
- Best use:
  rep-counting and segmentation sanity checks, especially for squats.
- Why it fits:
  the official site includes squats and time-synchronized workout recordings with pose estimates.
- Caveat:
  this is stronger for counting than for form-fault labels.

### 5. UI-PRMD

- Site: https://avakanski.github.io/ui-prmd.html
- Best use:
  movement-quality scoring pipeline sanity checks and replay tooling.
- Why it fits:
  the official site provides repeated rehabilitation movements, including deep squat, from Kinect and Vicon capture.
- Caveat:
  rehabilitation motion is not the same as loaded strength training.

### 6. KIMORE

- Site: https://vrai.dii.univpm.it/content/kimore-dataset
- Best use:
  clinician-scored movement-quality experiments.
- Why it fits:
  the official site provides RGB, depth, skeletons, engineered features, and clinician scores.
- Caveat:
  useful for validating the scoring pipeline shape, but not for squat, bench, deadlift, or pulldown specificity.

## Recommended proof-of-concept benchmark stack

Use a mixed stack instead of waiting for one perfect dataset:

1. Low-friction smoke test
   Gym Workout/Exercises Video to confirm Vision can detect stable joints from saved `.mp4` workout clips.
2. Public squat benchmark
   Fitness-AQA squat subset for action-quality scoring.
3. Public repetition benchmark
   MM-Fit and Fit3D clips for rep counting and multi-view robustness.
4. Public coaching benchmark
   QEVD Fit-Coach-Benchmark for cue timing and feedback relevance.
5. Custom golden set
   Your own labeled clips for `latPulldown`, `dumbbellBench`, `deadlift`, and `bench`.

## Custom golden set you should build

Public data will not fully cover your exact cues, camera framing, and exercise list. For a convincing v1, record a small internal benchmark:

- 8 to 12 lifters
- 5 exercises
- 2 camera angles per exercise
- 2 lighting conditions
- 3 clip types per exercise:
  good form, common warning, clear error

Label each clip with:

- rep count
- which cues should fire
- when the cue should first fire
- whether the clip should stay silent

This gives you the benchmark that matters most: "does this app behave correctly on the exact exercises and filming conditions we expect real users to use?"

## Real-device smoke checklist

- Camera permission denied path shows the settings CTA.
- Live pose disappears cleanly when no person is in frame.
- Rep count stays stable when the user pauses at the top or bottom.
- Spoken cues do not spam repeatedly.
- Ending a session saves exactly one new session to history.
- Front-camera mirror view still produces correct left/right cueing.
