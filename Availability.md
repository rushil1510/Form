## The Two Accuracy Ceilings

There are two completely separate systems here and you have very different levels of control over each:

---

### Stage 1: Joint Detection — Apple's Black Box

`VNDetectHumanBodyPoseRequest` is a pre-trained CoreML model that Apple ships inside iOS. **You cannot retrain it, fine-tune it, or improve it.** You get 19 joint positions + confidence scores back and that's the ceiling.

What *does* affect its accuracy — and what you control:
- **Camera angle** — frontal view is best; diagonal is worse. You could guide the user to stand correctly.
- **Distance** — 6–8 feet is the sweet spot. Too close and joints get cropped; too far and confidence drops.
- **Lighting** — Vision struggles in dim gyms. You can warn the user.
- **Clothing** — dark clothes on dark backgrounds kills contrast. Nothing you can do about this.
- **Occlusion** — a barbell across the hips blocks the hip joint. You can detect low-confidence joints and tell the user to reframe.

Apple passively improves the model with iOS updates. You benefit for free.

---

### Stage 2: The Rule Engine — You Own Everything Here

This is where **almost all real accuracy gains live**, and it's entirely under your control. The Vision output is actually quite solid for most gym movements. The bottleneck right now is that the rule engine is a collection of naive stubs. Here's the priority-ordered roadmap:

---

**1. `VNDetectHumanBodyPose3DRequest` — the single biggest win (iOS 17+)**

This API already exists and you're not using it. It returns **3D joint positions (x, y, z)** using monocular depth estimation from a single camera. For form analysis, this is massive:

- In 2D, you can't tell if someone's knee is *actually* forward or if it just *looks* forward due to camera angle
- In 3D, knee tracking over the toe becomes unambiguous
- Bar path on a deadlift (is the wrist traveling straight up or swinging?) becomes measurable

Swap `VNDetectHumanBodyPoseRequest` → `VNDetectHumanBodyPose3DRequest` and your entire rule engine becomes significantly more accurate with no other changes.

---

**2. Per-User Calibration (Adaptive Thresholds)**

Right now `RepCounter` uses hardcoded `lowThreshold: 95°, highThreshold: 150°`. These are guesses. A 6'4" person's squat range of motion is completely different from a 5'2" person's.

The fix: on the first session, run a "calibration set" — ask the user to do 3 slow reps, record the min/max angles, then set thresholds as `min + 10°` and `max - 10°`. Store these in `UserDefaults` per exercise. This alone would dramatically improve rep counting accuracy.

---

**3. Phase-Aware Analysis (Temporal Context)**

Currently `SquatAnalyzer.analyze()` looks at one frame in isolation. It has no idea if the user is standing up, going down, at the bottom, or coming back up. This causes two problems:

- False positives: "knees out" warning fires when the user is just standing still
- Missed faults: some errors only matter at specific phases (e.g., butt wink only matters at the very bottom)

The fix: track phase in the analyzer, not just in `RepCounter`. Feed the current `RepPhase` into `analyze()`. Only check depth at the bottom of the descent.

---

**4. Bilateral Asymmetry Detection**

This is a real injury risk signal that's completely free from existing data. Compare left vs right joint angles every frame:

```swift
let leftKneeAngle  = GeometryHelpers.angle(a: leftHip, b: leftKnee, c: leftAnkle)
let rightKneeAngle = GeometryHelpers.angle(a: rightHip, b: rightKnee, c: rightAnkle)

if abs(leftKneeAngle - rightKneeAngle) > 15 {
    return .warning("Left/right imbalance detected — check weak side")
}
```

No new APIs. No ML. Just a subtraction.

---

**5. Multi-Frame Fault Persistence (Reduce False Positives)**

Right now a single bad frame triggers a warning. Vision's output jitters frame-to-frame. The fix: only fire a warning after the same fault appears for N consecutive frames (e.g., 5 frames = ~167ms at 30fps). This eliminates jitter-induced false alarms with minimal code:

```swift
private var faultFrameCount: [String: Int] = [:]
private let faultConfirmationFrames = 5
```

---

**6. Velocity / Acceleration Tracking**

You're not just recording *where* joints are — you can record *how fast* they're moving. Store the last N joint positions with timestamps and compute velocity. This unlocks:

- **Controlled descent detection**: a squat that drops too fast is dangerous under load
- **Sticking point detection**: where in the range of motion does bar velocity drop (weakest joint angle)
- **Rep tempo tracking**: 3-1-1 (3s down, 1s pause, 1s up) is a real programming variable

---

**7. Bar Path Tracking (Wrist Proxy)**

For deadlift and bench, the barbell path is critical — but you don't have a barbell sensor. The wrists *are* the barbell (approximately). Track wrist `x` position across all frames in a rep:

- Good deadlift: wrist X stays nearly constant (bar stays over mid-foot)
- Bad deadlift: wrist X drifts forward (bar swings out, stresses lower back)

This requires storing wrist positions across the rep, which `RepCounter` can expose.

---

**8. Create ML — Training Your Own Rule Classifier (Advanced)**

If you collect enough labeled data (video of good form vs bad form, annotated), you can train a classifier in **Create ML** (Apple's no-code ML tool, free in Xcode) that:

- Takes a sequence of JointMaps (one rep's worth of frames)
- Outputs a probability distribution over form quality classes

This replaces the hand-written geometry rules in Stage 2 with a learned model. The Vision Stage 1 output becomes the *input features* for your own model. This is the path that real sports analytics products take eventually — but it requires labeled training data which is the hard part.

---

## Summary: What's Apple vs What's Yours

| Question | Answer |
|----------|--------|
| Can we improve joint detection accuracy? | Only indirectly — guide camera angle, distance, lighting |
| Is the rule engine ours to improve? | **100% yes** — it's plain Swift geometry |
| Single biggest API-level win? | Switch to `VNDetectHumanBodyPose3DRequest` (iOS 17, already available) |
| Biggest logic-level win? | Per-user calibration + phase-aware analysis |
| Can we train our own model? | Yes, via Create ML — but you need labeled video data first |

The tl;dr: Apple owns the joints, you own everything you do with them. And there's a lot you can do.