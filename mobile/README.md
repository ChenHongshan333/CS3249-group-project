# CookTogether Mobile App (Flutter)

One Flutter codebase builds the iOS app, the Android app, and a web preview for quick UI checks. The screens communicate with smart glasses through a single interface, [`GlassesService`](lib/glasses/glasses_service.dart), keeping wearable hardware integration cleanly decoupled from the UI layer.

The backend API contract is documented in [`docs/api.md`](../docs/api.md). By default, the app connects to the team's hosted backend (`https://cookalong-backend.onrender.com`); you can override it under **Profile → Developer → Backend URL**, or clear the URL to use built-in offline demo answers. When the backend is unreachable, the app speaks *"Sorry, I couldn't reach the assistant…"* rather than silently falling back to demo replies.

> **Hosted backend cold start:** The backend runs on Render's free plan, which sleeps after 15 idle minutes and takes up to ~60 seconds to wake. CookTogether automatically pings `/health` when the app opens and when you reach *Get Ready*, so it is usually warm before the first question.

---

## Compiling & Running the Flutter App

> **Evaluation tip (iOS):** Compiling and signing the iOS app for a physical iPhone requires **macOS, Xcode, and an Apple Developer account** (especially for Meta Wearables DAT entitlements). Evaluators do not need to compile the iOS build themselves if joining via **TestFlight**—see the root [`README.md`](../README.md#2-mobile-application-testflight-evaluation).

### Prerequisites

| Target | Host OS | Required Tools & Notes |
| --- | --- | --- |
| **Shared** | Any | **Flutter SDK** (stable channel, **Dart `^3.12.2`**) |
| **iOS** *(Primary / Meta Glasses)* | **macOS only** | **Xcode 26.4+**, **CocoaPods** (`pod`), physical iPhone running **iOS 17.6+**, and an **Apple Developer account** for code signing (`com.orion.cooktogether`). Builds signed with a free personal Apple ID expire after 7 days; paid Apple Developer accounts support TestFlight distribution. |
| **Android** | macOS, Windows, or Linux | **Android Studio / Android SDK** (`minSdk 31` / Android 12+), **Java 17** (`JDK 17`), physical Android device with USB debugging enabled. |
| **Web** *(UI check only)* | macOS, Windows, or Linux | **Chrome**. Supports simulated glasses only—native Meta DAT, `whisper.cpp` FFI, and TFLite NLU do not run on Web. |

### Step 1 — Install Flutter Dependencies & Check ML Assets

```bash
cd mobile
flutter pub get
```

- **Bundled TFLite intent model:** `assets/models/all-MiniLM-L6-v2-quant.tflite` (~22 MB) and `assets/models/vocab.txt` are already committed in the repository and packaged into the app bundle automatically.
- **On-device Whisper model (`base.en`):** `ggml-base.en.bin` is downloaded automatically on first mobile launch into the app's local storage directory (`WhisperTranscriber.ensureModelDownloaded()`); no manual model download step is needed during compilation.

### Step 2 — Compile & Run for iOS (Physical iPhone / TestFlight)

1. **Install CocoaPods dependencies:**

   ```bash
   cd mobile/ios
   pod install
   cd ..
   ```

   > `ios/Podfile` targets iOS 17.6 and automatically configures `whisper_kit` with C++17 and Apple's `Accelerate` framework flags.

2. **Configure Apple Developer Signing in Xcode:**

   ```bash
   open ios/Runner.xcworkspace
   ```

   - Select the **Runner** project → **Runner** target → **Signing & Capabilities**.
   - Enable **Automatically manage signing** and select your **Apple Developer Team** (this also populates `$(DEVELOPMENT_TEAM)` inside `ios/Runner/Info.plist`'s `MWDAT` dictionary, which Meta's toolkit requires).
   - If using your own Apple Developer account and `com.orion.cooktogether` is already claimed, update **Bundle Identifier** to a unique identifier.

3. **Compile and install on a connected iPhone:**

   ```bash
   flutter devices                           # note your iPhone's device ID
   flutter run --release -d <ios-device-id>  # recommended for testing real Meta Glasses & Whisper speed
   # or debug build:
   flutter run -d <ios-device-id>
   ```

4. **Build an `.ipa` Archive for TestFlight (optional):**

   ```bash
   flutter build ipa --release
   ```

   Alternatively, open `ios/Runner.xcworkspace` in Xcode and run **Product → Archive → Distribute App → TestFlight & App Store**.

### Step 3 — Compile & Run for Android

1. Connect an Android 12+ (`API 31+`) phone with USB debugging enabled and verify detection:

   ```bash
   flutter devices
   ```

2. Compile and run directly on the device:

   ```bash
   flutter run --release -d <android-device-id>
   ```

3. Or build a standalone release APK:

   ```bash
   flutter build apk --release
   # Output: build/app/outputs/flutter-apk/app-release.apk
   ```

### Step 4 — Run on Web (Quick UI Preview)

```bash
flutter run -d chrome
```

### Step 5 — Static Analysis & Automated Tests

```bash
flutter analyze   # Dart & Flutter lints / type checks
flutter test      # unit and widget test suite
```

---

## Simulated or Real Glasses

The app uses real Ray-Ban Meta glasses if it is already registered with the Meta AI app. Otherwise it shows *"Glasses not connected"*, and step checks fall back to the phone camera.

Simulated glasses (Meta's Mock Device Kit) are available for demos, testing, and the web build, and are hidden from normal users. Turn on **Profile → Developer → Simulated glasses when no real ones** to show them as connected and use their photos. The same section picks the simulated model and simulates a touchpad tap.

### Connect Real Glasses

Needs the **Meta AI app V290 or newer** and **glasses firmware V128 or newer**.

1. In the Meta AI app, open **Settings → App Info** and tap the version number five times. Turn on **Developer Mode**. If your glasses show an **Install** button there, tap it and keep the app open until it finishes.
2. Install CookTogether on the same phone (via TestFlight or the compilation steps above).
3. In CookTogether, open a recipe, tap **Connect** next to the glasses status, then **Connect my glasses**.
4. Meta AI opens. Approve the unverified app; this is normal in Developer Mode. Meta AI returns to CookTogether through the `cookalong://` link.
5. Allow camera access when asked.

If the glasses are turned off later, *Get Ready* shows *"Glasses disconnected"*. Turn them on, tap **Reconnect**, then **Reconnect glasses**.

After that, **Check** on the cooking screen takes a photo with the glasses. The glasses camera turns on only while the photo is taken. If it can't take a photo (glasses folded, too warm, or not connected), the app says why instead of checking a blank image.

Speech and spoken replies route through the glasses as a Bluetooth HFP headset, so they work without repeating camera registration.

---

## Voice Control & Wake Word

CookTogether features hands-free voice assistance powered by native 16 kHz PCM Voice Activity Detection (VAD), local Whisper (`base.en`), and an on-device hybrid TFLite (`all-MiniLM-L6-v2`) intent parser.

### Wake Phrase

To trigger CookTogether hands-free, use the wake word:

* **Primary wake word:** **"Hey Cooky"**
* **Accepted variations & greetings:**
  * Greeting prefixes: `"Hey"`, `"Hi"`, `"OK" / "Okay"`, `"Hello"`, `"Yo"`
  * Phonetic / name variants: `"Cooky"`, `"Cookie"`, `"CookTogether"`, `"Cook Along"`, or standalone `"Cooky"` / `"Cookie"`

### How to Speak Commands

1. **In one breath:**
   * *"Hey Cooky, next step"*
   * *"Hey Cooky, how much salt do I add?"*
   * *"Hey Cooky, set a timer for 5 minutes"*
   * *"Hey Cooky, does this look ready?"* / *"check this step"*
2. **Wake word first, then command:**
   * Say *"Hey Cooky"* alone.
   * The status changes to **"Listening… speak now"**.
   * Speak your command or question within the 8-second window.

### Direct Question Answering (No Wake Word Needed)

When CookTogether asks you a direct question (for example, *"Skip this step without checking? Say check to take a look, or skip to move on"* or *"Would you like a timer?"*):

* The microphone automatically turns on in active listening mode immediately after the prompt is spoken.
* **You do not need to say "Hey Cooky"**—simply answer directly with *"skip"*, *"check"*, *"yes"*, *"no"*, etc.

### Other Input Modes

* **Tap-to-Speak:** Tap the microphone button in the cooking dock to speak immediately without the wake word.
* **Text Input:** Tap the keyboard icon or **More ("...") → Type instead** to type commands or questions manually.
* **Microphone Routing:** Audio is recorded through the Meta glasses' Bluetooth microphone if connected, or automatically falls back to the phone's built-in microphone when glasses are unavailable.

---

## Native Meta Glasses Configuration Reference

These native platform configurations are already set up in the repository. Preserve them if changing the bundle/application ID or app name:

- `ios/Runner/Info.plist`: the `MWDAT` dictionary (Developer Mode values & `$(DEVELOPMENT_TEAM)`), the `cookalong` URL scheme, `fb-viewapp` query scheme, external accessory protocol (`com.meta.ar.wearable`), Bluetooth background modes, and local network access.
- `ios/Runner/SceneDelegate.swift`: forwards the `cookalong://` Meta AI callback URL to the plugin (`MetaWearablesDatHandleURL`).
- `ios/Runner/AppDelegate.swift`: native Bluetooth HFP audio routing and 16 kHz PCM pre-roll VAD engine.
- `android/app/src/main/AndroidManifest.xml`: Meta app ID and client token (`0` for Developer Mode), analytics opt-out, Bluetooth permissions, and the `cookalong://` intent filter.
- `android/app/src/main/kotlin/com/cs3249/mobile/MainActivity.kt`: extends `FlutterFragmentActivity`, implements Bluetooth SCO mic persistence and 16 kHz PCM pre-roll VAD (`minSdk 31`).

Both platforms opt out of Meta's toolkit analytics so user sessions do not transmit usage telemetry to Meta.

If registration fails with *"not set up for Meta glasses"*, call `MetaWearablesDat.dumpDiagnostics()` from a debug build and resolve the reported items. See also [`meta_wearables_dat_flutter`](https://pub.dev/packages/meta_wearables_dat_flutter).
