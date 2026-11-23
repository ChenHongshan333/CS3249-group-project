# CookTogether

**CookTogether** is a voice-first, vision-enabled hands-free cooking assistant for beginner cooks built for CS3249. Paired with **Ray-Ban Meta smart glasses** (with seamless iPhone camera and microphone fallback), it guides users through a recipe one step at a time—answering contextual cooking questions, adapting steps on the fly for missing ingredients or healthier swaps, managing timers, and visually checking cooking progress from the cook's point of view.

> **Naming note:** The application is branded **CookTogether** (wake word: *"Hey Cooky"*). A few underlying technical identifiers retain the project's early working name, **CookAlong**—notably the hosted backend URL (`https://cookalong-backend.onrender.com`) and the iOS/Android Meta AI callback scheme (`cookalong://`).

---

## Core Task & System Architecture

Beginner cooks often struggle to follow recipes with wet or messy hands, judge whether an intermediate step looks right, or adapt when an ingredient is missing. CookTogether solves this end-to-end:

1. **Prepare & Adapt (*Get Ready*):** The cook picks one of four built-in beginner recipes, checks off available ingredients (marking any missing items to leave out or substitute), and optionally selects healthier ingredient swaps.
2. **Guided Hands-Free Cooking:** During cooking, CookTogether reads each step aloud through the glasses' speakers. The cook triggers commands hands-free using **"Hey Cooky"** (or responds directly to assistant questions without repeating the wake word), asks contextual questions, sets/manages timers, and requests visual step checks (*"Hey Cooky, check this step"* / *"Does this look ready?"*).
3. **POV Vision Feedback:** On a visual check, CookTogether captures a fresh point-of-view snapshot through the Meta glasses camera (or iPhone camera fallback), evaluates it against the current step's visual completion criteria, and speaks concise, food-safe feedback.

```text
Ray-Ban Meta Glasses (POV Camera + Bluetooth HFP Mic/Speakers)
        │  Meta Wearables DAT SDK + Native BT HFP Audio Routing
        ▼
Flutter Mobile App (mobile/)
  ├── Native 16 kHz PCM Pre-Roll Ring-Buffer & Adaptive RMS VAD (iOS Swift / Android Kotlin)
  ├── On-Device Speech-to-Text (whisper.cpp base.en via FFI) + Wake Word ("Hey Cooky")
  ├── Hybrid On-Device Intent Parser (quantized all-MiniLM-L6-v2 TFLite + Rule Guardrails)
  └── Step Adapter & Speech / TTS Controller
        │  HTTPS JSON (docs/api.md: /ask, /check-step, /log)
        ▼
Hosted FastAPI Backend on Render (server/)
  ├── Phase-Aware Prompts (Opening / Cooking / Vision Check)
  ├── Deterministic Safety Guardrails & Offer/Action Validator (app/safety.py)
  └── Pluggable Multimodal Vision/LLM Client (OpenRouter / Claude / OpenAI / Qwen)
```

---

## Models, APIs, and Services Utilized

| Layer | Model / API / Service | Purpose |
| --- | --- | --- |
| **Hosted Backend** | FastAPI hosted on **Render** (`https://cookalong-backend.onrender.com`) | Proxies LLM/vision requests (keeping API keys off mobile devices), enforces deterministic safety guardrails, and logs session telemetry to SQLite. |
| **Cloud Multimodal LLMs** | Pluggable backend supporting **OpenRouter** (default `anthropic/claude-haiku-5.5`), **Anthropic Claude** (`claude-haiku-5-5`), **OpenAI** (vision-capable models), **Alibaba Cloud Qwen** (`qwen-vl-max`), and `fake` mode | Powers `/ask` (conversational Q&A, structured offers/actions, opening step adaptation) and `/check-step` (multimodal visual progress checks). |
| **On-Device Speech-to-Text** | **Whisper `base.en`** (`ggml-base.en.bin`) via `whisper_kit` (`whisper.cpp` C++ FFI) | Local hands-free transcription of 16 kHz `.wav` utterances from the native VAD engine (auto-downloaded on first launch; falls back to OS `speech_to_text`). |
| **On-Device Semantic NLU** | Quantized **`all-MiniLM-L6-v2`** (`mobile/assets/models/all-MiniLM-L6-v2-quant.tflite`) via `tflite_flutter` | 384-dim sentence embeddings with pre-computed intent centroids for low-latency local command classification. |
| **Smart Glasses SDK** | **Meta Wearables Device Access Toolkit** (`meta_wearables_dat_flutter` `^1.0.0`) | Pairs with Ray-Ban Meta glasses via Meta AI app, manages device telemetry/permissions, captures on-demand POV snapshots, and provides Mock Device Kit parity. |
| **Native Mobile Audio & Vision** | iOS `AVAudioEngine` / `AVAudioSession`, Android `AudioRecord` / `AudioManager`, `flutter_tts`, `image_picker` | Persistent Bluetooth HFP microphone routing, native 16 kHz PCM VAD capture, spoken TTS responses, and phone-camera fallback. |

---

## Main Codebase Components

| Path | Role | Key Files |
| --- | --- | --- |
| [`mobile/`](mobile/) | Flutter iOS/Android/Web app | [`lib/glasses/glasses_service.dart`](mobile/lib/glasses/glasses_service.dart), [`lib/glasses/upright_photo.dart`](mobile/lib/glasses/upright_photo.dart), [`lib/services/voice_controller.dart`](mobile/lib/services/voice_controller.dart), [`lib/services/tflite_intent_classifier.dart`](mobile/lib/services/tflite_intent_classifier.dart), [`lib/services/voice_intent_parser.dart`](mobile/lib/services/voice_intent_parser.dart), [`lib/services/step_adapter.dart`](mobile/lib/services/step_adapter.dart), [`lib/services/whisper_transcriber.dart`](mobile/lib/services/whisper_transcriber.dart), [`lib/screens/cooking_screen.dart`](mobile/lib/screens/cooking_screen.dart) |
| [`mobile/ios/`](mobile/ios/) & [`mobile/android/`](mobile/android/) | Native platform bridges | [`ios/Runner/AppDelegate.swift`](mobile/ios/Runner/AppDelegate.swift) & [`android/.../MainActivity.kt`](mobile/android/app/src/main/kotlin/com/cs3249/mobile/MainActivity.kt) (Bluetooth HFP routing + native 16 kHz PCM VAD); [`ios/Runner/SceneDelegate.swift`](mobile/ios/Runner/SceneDelegate.swift) & [`ios/Runner/Info.plist`](mobile/ios/Runner/Info.plist) (Meta DAT registration callback) |
| [`server/`](server/) | Python FastAPI backend | [`app/main.py`](server/app/main.py) (API routes), [`app/prompts.py`](server/app/prompts.py) (system prompts), [`app/safety.py`](server/app/safety.py) (safety guardrails & action validation), [`app/llm/`](server/app/llm/) (provider adapters), [`evals/`](server/evals/) (workflow evaluation scripts) |
| [`docs/api.md`](docs/api.md) | Shared API contract | JSON request/response schemas and design decisions for `/ask`, `/check-step`, and `/log` |
| [`web/`](web/) | Early React UI prototype | Kept for design reference only; the evaluated system is [`mobile/`](mobile/) + [`server/`](server/) |

---

## Setup & Running the System

No user accounts, logins, or personal data are required to test CookTogether—the app opens directly into four built-in beginner recipes with ingredient checklists and healthier swaps.

### 1. Backend (Hosted — Ready Out of the Box)

The backend running our submitted `server/` code is **already hosted on Render**:

- **Live Backend URL:** `https://cookalong-backend.onrender.com`
- **Health Check:** `https://cookalong-backend.onrender.com/health`

The mobile app is pre-configured to connect to this hosted backend automatically, so **evaluators do not need to supply any paid LLM API keys**.

> **Cold-start note:** Render's free tier sleeps after 15 minutes of inactivity and takes up to ~60 seconds to wake. CookTogether automatically pings `/health` when the app opens and on the *Get Ready* screen so the server is typically warm before the first question.

To inspect or run the backend locally (including offline testing with `LLM_PROVIDER=fake`), see [`server/README.md`](server/README.md).

### 2. Mobile Application (TestFlight Evaluation)

Compiling and signing the iOS application for a physical iPhone (including the Meta Wearables DAT entitlements) requires an **Apple Developer account** and macOS with Xcode. To save the evaluation team from needing an Apple Developer account or configuring Xcode signing:

- **We propose distributing CookTogether to the evaluation team via Apple TestFlight.**
- Our team will reach out by email to request the evaluation team's **Apple ID email address(es)** so we can add you as TestFlight testers.
- Once invited:
  1. Install Apple's **TestFlight** app from the iOS App Store.
  2. Open the TestFlight invitation email on your iPhone and accept the invite.
  3. Install **CookTogether** directly from TestFlight and grant Microphone, Speech Recognition, Bluetooth, Local Network, and Camera permissions when prompted.

If you prefer to compile the Flutter application yourself from the submitted source code (iOS, Android, or Web), complete step-by-step compilation instructions are provided in [`mobile/README.md`](mobile/README.md).

### 3. Connecting Ray-Ban Meta Glasses

**Requirements:** Ray-Ban Meta glasses paired to the same phone, **Meta AI app V290 or newer**, and **glasses firmware V128 or newer**.

1. **Enable Developer Mode in Meta AI:** Open the **Meta AI** app → **Settings** → **App Info** → tap the version number **five times** → enable **Developer Mode**. If your glasses show an **Install** button for the toolkit update on that screen, tap it and keep Meta AI open until it completes.
2. **Start Pairing from CookTogether:** Open **CookTogether**, select any recipe to enter the *Get Ready* screen, tap **Connect** next to the glasses status banner, and tap **Connect my glasses**.
3. **Approve in Meta AI:** Meta AI opens automatically. Approve the unverified app prompt (expected in Developer Mode). Meta AI redirects back to CookTogether via the `cookalong://` URL scheme.
4. **Grant Glasses Camera Permission:** Allow camera access when prompted so CookTogether can take point-of-view step photos.
5. **Reconnecting Later:** If the glasses power off or disconnect, *Get Ready* shows *"Glasses disconnected"*. Turn the glasses back on, tap **Reconnect**, and then **Reconnect glasses**.
6. **Audio & Vision Behavior:** Spoken prompts and voice input route over Bluetooth HFP through the glasses' speakers and microphone. When you say *"Hey Cooky, check this step"* (or tap **Check**), the glasses camera activates **only for the duration of the single snapshot** and immediately turns off afterward.

### 4. Trying CookTogether Without Meta Glasses

Every core cooking and conversational feature works on an iPhone **without Meta glasses**:

- **Camera fallback:** When no real glasses are connected, tapping **Check** or asking *"Does this look ready?"* automatically opens the phone camera for step checks.
- **Voice & text input:** Say **"Hey Cooky"** (or tap the microphone button) to speak via the iPhone microphone, or tap the keyboard icon / **More ("...") → Type instead** to interact entirely by typing.
- **Simulated glasses (Mock Device Kit):** Open **Profile → Developer → Simulated glasses when no real ones** to exercise the Meta Wearables Mock Device Kit path without hardware.
- **Live glasses demo option:** If the evaluation team does not have Ray-Ban Meta glasses on hand and would like to evaluate the live glasses hardware end-to-end, please let us know—we are happy to arrange a short online session with our group.

---

## What Is New: Technical Challenges & Innovations

Our system addresses four core technical challenges in building a practical, hands-free kitchen CUI—centered on **integrating Ray-Ban Meta smart glasses reliably into a real-time multimodal voice loop**. Every component below is marked in source code with a comment starting with `INNOVATION:` so graders can locate them directly (`grep -rn "INNOVATION:" mobile/ server/`).

### 1. Meta Glasses Integration & Hardware-Aware Capture *(Primary Emphasis)*

Integrating consumer smart glasses into a hands-free cooking workflow exposes several hardware and SDK constraints that do not exist in standard phone apps:

- **Hardware-Agnostic Interface & Mock Device Kit Parity (`glasses_service.dart`):** All UI screens talk exclusively to a single reactive `GlassesService` abstraction over `meta_wearables_dat_flutter`, unifying real Ray-Ban Meta hardware, live battery/hinge/don telemetry, and the Meta Mock Device Kit under one lifecycle.
- **Bluetooth HFP-to-Camera Contention Coordination (`voice_controller.dart`):** Keeping the glasses' Bluetooth HFP (call-mode) microphone link active can block the wearable camera stream from starting. Before any glasses snapshot, `prepareForPhoto()` stops active listening, awaits the spoken *"Look at your food and hold still"* TTS cue, explicitly releases the Bluetooth HFP mic link, captures the photo, and automatically restores headset audio on the next turn.
- **On-Demand Transient Camera Streaming & Resilient Recovery (`glasses_service.dart`):** Continuous video streaming drains glasses battery, triggers thermal throttling, and keeps the privacy LED lit. `_takeGlassesPhoto()` opens the stream strictly for one high-quality JPEG snapshot and tears it down immediately (guarding against stopping an unstarted session, which can freeze the native SDK). `_captureFromRealGlasses()` adds concurrency guards, closed-hinge checks, automatic camera-permission retry, a 15-second auto-reconnect window for transient post-capture link drops, and actionable spoken error translation.
- **Off-Isolate EXIF & 90° Upright Photo Correction (`upright_photo.dart`):** Meta DAT snapshots arrive rotated 90° anticlockwise without reliable orientation metadata. `uprightGlassesPhoto()` inspects EXIF tags and rotates/re-encodes frames inside a background `Isolate.run` so the Flutter UI never janks and the vision model receives upright food photos.
- **Persistent Native Bluetooth HFP Audio Routing (`AppDelegate.swift`, `MainActivity.kt`):** Mobile OSes frequently drop Bluetooth headset microphones back to the built-in phone mic between TTS and STT turns. Native route observers on iOS (`AVAudioSession.routeChangeNotification`) and Android (`AudioManager.OnCommunicationDeviceChangedListener`) automatically reclaim the glasses' microphone throughout a cooking session.

### 2. Kitchen-Resilient Native Voice Activity Detection (VAD)

Standard mobile speech recognizers cut users off mid-pause or falsely trigger on sizzling pans and extractor fans. We implemented custom native **16 kHz mono PCM capture engines** in Swift (`AVAudioEngine`) and Kotlin (`AudioRecord`) featuring a **350 ms pre-roll ring buffer** (so initial syllables of *"Hey Cooky"* or commands are never clipped) and a **live-tunable adaptive RMS noise-floor tracker** (exposed via the in-app VAD tuning sheet) before passing clean `.wav` utterances to on-device Whisper `base.en`.

### 3. Hybrid On-Device Intent Parser

Routing simple navigation or timer commands through a cloud LLM adds noticeable latency while hands are busy, yet pure keyword regexes miss natural phrasing (*"I'm done with this step"*, *"check my pan"*) or misfire on cooking questions (*"how long should I set the timer if..."*). We combine an **on-device quantized `all-MiniLM-L6-v2` TFLite sentence-embedding classifier** (`tflite_intent_classifier.dart`, pre-computing 384-dim intent centroids at startup and matching via cosine similarity) with an **explicit question-vs-request guardrail and deterministic rule fallback** (`voice_intent_parser.dart`), keeping local commands instant while routing open-ended questions safely to the backend LLM.

### 4. Backend Safety Guardrails & Dynamic Recipe Adaptation

LLM-generated cooking advice carries real safety risks (e.g., claiming meat is cooked through from a photo, declaring food allergy-safe, or generating unsafe rewritten steps like *"boil oil"*):

- **Deterministic Food-Safety & Allergy Guardrail (`server/app/safety.py`):** Every LLM reply passes through a clause-aware post-processor before TTS playback. Unsafe doneness or allergy claims are replaced in-place with safe verification advice—while preserving valid negated caveats (*"a photo can't confirm chicken is cooked through"*) and automatically downgrading unsafe visual check verdicts to `"unsure"`.
- **Phase-Scoped Action Validation & Hybrid Step Adaptation (`server/app/safety.py`, `mobile/lib/services/step_adapter.dart`):** Structured `offer` and `action` payloads (`start_timer`, `next_step`, `tick_ingredient`, `adapt_steps`, `custom_swap`) are strictly validated against the active cooking phase and current recipe state, truncated JSON replies are recovered cleanly, and missing-ingredient/swap rewrites combine deterministic hand-curated & clause-aware rules with LLM step adaptation while preventing unsafe instructions.

### `INNOVATION:` Code Marker Index

Run `grep -rn "INNOVATION:" mobile/ server/` from the repository root to jump directly to every annotated block:

| Area | File | What Is Marked |
| --- | --- | --- |
| **Meta Glasses** | [`mobile/lib/glasses/glasses_service.dart`](mobile/lib/glasses/glasses_service.dart) | Hardware-agnostic `GlassesService` & Mock Kit parity; resilient capture recovery; on-demand transient camera streaming |
| **Meta Glasses** | [`mobile/lib/glasses/upright_photo.dart`](mobile/lib/glasses/upright_photo.dart) | Off-UI-isolate EXIF & 90° upright photo rotation |
| **Meta Glasses** | [`mobile/lib/services/voice_controller.dart`](mobile/lib/services/voice_controller.dart) | Bluetooth HFP-to-camera contention coordination (`prepareForPhoto`) |
| **Meta Glasses** | [`mobile/ios/Runner/AppDelegate.swift`](mobile/ios/Runner/AppDelegate.swift) | Persistent iOS Bluetooth HFP headset mic routing |
| **Meta Glasses** | [`mobile/android/app/src/main/kotlin/com/cs3249/mobile/MainActivity.kt`](mobile/android/app/src/main/kotlin/com/cs3249/mobile/MainActivity.kt) | Persistent Android Bluetooth SCO headset mic routing |
| **Native VAD** | [`mobile/ios/Runner/AppDelegate.swift`](mobile/ios/Runner/AppDelegate.swift) | Native iOS 16 kHz PCM 350 ms pre-roll ring buffer & adaptive RMS VAD |
| **Native VAD** | [`mobile/android/app/src/main/kotlin/com/cs3249/mobile/MainActivity.kt`](mobile/android/app/src/main/kotlin/com/cs3249/mobile/MainActivity.kt) | Native Android 16 kHz PCM 350 ms pre-roll ring buffer & adaptive RMS VAD |
| **Intent Parser** | [`mobile/lib/services/tflite_intent_classifier.dart`](mobile/lib/services/tflite_intent_classifier.dart) | Quantized `all-MiniLM-L6-v2` TFLite sentence-embedding centroid classifier |
| **Intent Parser** | [`mobile/lib/services/voice_intent_parser.dart`](mobile/lib/services/voice_intent_parser.dart) | Hybrid NLU with question-vs-request guardrail & rule fallback |
| **Safety & Adaptation** | [`server/app/safety.py`](server/app/safety.py) | Deterministic food-safety/allergy guardrail & phase-scoped action/step sanitizer |
| **Safety & Adaptation** | [`mobile/lib/services/step_adapter.dart`](mobile/lib/services/step_adapter.dart) | Hybrid deterministic + LLM dynamic recipe step adaptation |
