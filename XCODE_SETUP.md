# Xcode Setup — First-Time Guide (novice)

Goal: create a local Xcode app project that builds the checked-in source files and runs on your iPhone.
Do NOT open the repo root directly in Xcode (it has a `Package.swift` → opens as a test harness package, not the iOS app). Create a fresh app project and point it at the existing source.

Repo root (call it REPO)

Checked-in app source root:
`REPO/Form/Form`

---

## 0. Prereqs
- Xcode installed (you have it at /Applications/Xcode.app).
- A free Apple ID (your normal one works).
- A USB cable + your iPhone (iOS 17+). Simulator can't do camera, so a real device is required.

## 1. Create the project
1. Open Xcode → **Create New Project…** (or File → New → Project, ⇧⌘N).
2. Top tab **iOS** → choose **App** → Next.
3. Fill in:
   - **Product Name:** `Form`
   - **Team:** leave for now (set in step 6)
   - **Organization Identifier:** `com.<yourname>` (e.g. `com.rushilmital`) — must be unique-ish
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Storage:** None
   - **Uncheck** "Include Tests" (we have our own terminal test harness)
4. Next. In the save dialog, navigate **into the REPO folder** and click **Create**.
   - This makes a local `REPO/Form/Form.xcodeproj`. Normal. (`.xcodeproj` is gitignored.)
   - The checkout already contains source files under `REPO/Form/Form`; do not delete or replace that folder.
   - If Xcode offers to create a git repo, **uncheck it** (you already have one).

## 2. Delete the 2 generated files that collide with the repo
In the left sidebar (Project Navigator, ⌘1), inside the yellow **Form** group you'll see template files. Right-click → **Delete** → **Move to Trash** for:
- `FormApp.swift`  (the repo provides its own `@main` — keeping both = "duplicate @main" error)
- `ContentView.swift`  (the repo defines `ContentView` inside its FormApp.swift)

**Keep** `Assets.xcassets` (it provides the `AccentColor` the app references).

## 3. Add the real source folders (by reference)
1. Right-click the yellow **Form** group → **Add Files to "Form"…**
2. Navigate to `REPO/Form/Form` and select these **5 folders** (⌘-click to multi-select):
   `App`  `Models`  `Features`  `Persistence`  `UI`
3. At the bottom of the dialog set:
   - **Copy items if needed:** ❌ UNCHECK (files already live in the repo)
   - **Added folders:** ● Create groups
   - **Add to targets:** ☑ Form (checked)
4. Click **Add**.

Do **not** add: `Package.swift`, `ValidationSupport/`, `FormTests/`, `docs/`, the `.md` files, `.build/`, `Info.plist` (handled in step 4).

Sanity check: the navigator should now show App, Models, Features, Persistence, UI groups with the Swift files inside.

## 4. Add the camera permission string (required — app crashes without it)
1. Click the blue **Form** project at the top of the navigator → select the **Form TARGET** → **Info** tab.
2. Hover any row → click **+** → choose **Privacy - Camera Usage Description**.
3. Set the value to: `Form uses your camera to analyze exercise form in real time. Video never leaves your device.`
(You can ignore the repo's `Info.plist` file — these settings live in the target now. Microphone permission is NOT needed; speech playback doesn't require it.)

## 5. Deployment target + orientation
Target → **General** tab:
- **Minimum Deployments → iOS:** set to **17.0**.
- **Deployment Info → iPhone Orientation:** check **Portrait** only (uncheck the Landscape boxes).

## 6. Signing (so it can run on your phone)
1. Xcode → **Settings…** (⌘,) → **Accounts** → **+** → **Apple ID** → sign in.
2. Target → **Signing & Capabilities** tab:
   - ☑ **Automatically manage signing**
   - **Team:** pick **"(Your Name) (Personal Team)"**
   - If you see a red "Bundle Identifier is not available" error, change the **Bundle Identifier** to something unique like `com.<yourname>.FormPOC`.

## 7. Prepare the iPhone (one-time)
1. Plug the iPhone into the Mac. Unlock it. Tap **Trust This Computer** → enter passcode.
2. On iPhone: **Settings → Privacy & Security → Developer Mode → ON** → restart the phone → confirm after reboot. (iOS 16+ requires this for self-installed apps.)

## 8. Run it
1. In the Xcode toolbar (top-center), click the device/destination dropdown → select **your iPhone** (not a simulator).
2. Press **⌘R** (Build + install + launch).
3. **First launch will fail** with "Untrusted Developer". On the iPhone:
   **Settings → General → VPN & Device Management → (your Apple ID under Developer App) → Trust**.
4. Press **⌘R** again. The app launches; accept the camera permission prompt.

Free-account note: the app expires after ~7 days; just ⌘R again from Xcode to reinstall. Fine for a demo.

## 9. Demo
Follow `DEMO.md` to trigger each form cue and screen-record. Use `docs/DEVELOPING.md` and `docs/ARCHITECTURE.md` when changing the implementation.

## 10. Adding new source files later
Step 3 added the folders as **groups** (static references), so new `.swift` files added to the repo afterwards are NOT automatically in your project. When you pull changes that add files (or create one yourself):
1. Right-click the matching group (e.g. `Models`, `Persistence`, or the relevant `UI` subgroup) → **Add Files to "Form"…**
2. Select the new file(s). **Copy items if needed:** ❌ UNCHECK. **Add to targets:** ☑ Form.
3. ⌘R.

Tell-tale sign you missed one: `swift test` passes, but the device build fails with **"Cannot find type 'X' in scope"**.

---

## Troubleshooting (error → fix)
- **"Invalid redeclaration / duplicate '@main'"** or **"Multiple commands produce …FormApp.swift"** → you didn't delete the generated `FormApp.swift` / `ContentView.swift` (step 2).
- **"Cannot find type 'X' in scope"** (e.g. SquatAnalyzer, JointMap) → a source folder wasn't added, or its files aren't in the target. Click the file → right panel **File Inspector** → **Target Membership** → check **Form**.
- **App crashes the instant the Workout tab opens** → missing camera usage string (step 4).
- **Camera is just black** → you're on the Simulator. Switch the run destination to your physical iPhone.
- **"Signing for 'Form' requires a development team"** → set Team (step 6).
- **iPhone not in the destination list** → unlock phone, re-trust computer, confirm Developer Mode is on.
- **Feedback banner stuck on "Good form!" while reps still count** → known capture quirk in `WorkoutView.setupPipeline()`; tell Claude, it's a small fix.
