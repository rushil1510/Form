# Form — Proof-of-Concept Demo Script

A mechanical run sheet for proving the app works and capturing evidence. Run on a
**physical iPhone (iOS 17+)** — the Simulator has no camera, so pose detection is dead there.

## Setup
- Prop the phone so the camera sees your **whole body**; good lighting, plain-ish background.
- Front camera is mirrored (intentional). Feedback is **spoken** (rate-limited to ~1 cue / 3s, so it won't spam).
- Demo only the three exercises with real coaching: **Squat, Lat Pulldown, Dumbbell Bench**.
  (Deadlift & Bench only count reps — analyzers are stubs that never critique form.)

## Per-exercise: do a clean rep, then deliberately break form to trigger the cue

### Squat — front-on, full body
- [ ] Skeleton tracks you; rep count increments on a full rep.
- [ ] Cave a knee inward → *"Keep your knees tracking over your toes."*
- [ ] Stop at a half-squat → *"Squat deeper — aim for hips below parallel."*

### Lat Pulldown — front-on, seated
- [ ] Stop the pull early → *"Pull the bar all the way to your chest…"*
- [ ] Shrug shoulders up at the bottom → *"Don't shrug!…"*
- [ ] Pull one arm noticeably higher → *"Keep both arms even…"*

### Dumbbell Bench — phone side-on at the end of the bench
- [ ] Let one arm lag → *"Left/Right arm is lagging…"*
- [ ] Stop pressing high (no chest stretch) → *"Lower the dumbbells more…"*

## Plumbing / persistence
- [ ] Rep count stays stable when you pause at the top/bottom (no double-count).
- [ ] Step out of frame → skeleton disappears cleanly (no frozen stale joints).
- [ ] End the session → exactly **one** new session appears in the **History** tab (live, no relaunch).
- [ ] Open that session → reps + form grade render.
- [ ] Deny camera permission once → the "Open Settings" screen shows.

## Evidence to capture
- [ ] 30s screen recording: skeleton tracking + one cue firing on bad form.
- [ ] Screenshot of `swift test` passing 23/23.

## Run the logic tests (Mac, no device)
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
