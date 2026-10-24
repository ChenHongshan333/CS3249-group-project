# CookAlong mobile app (Flutter)

Owners:

- Jaxon: Meta glasses connection (camera, mic, speakers) in `lib/glasses/`
- Screens in `lib/screens/`, styled by `lib/theme/`. Design rules for Claude Code are in [`.claude/skills/cookalong-flutter-ui/`](../.claude/skills/cookalong-flutter-ui/SKILL.md).

One Flutter codebase builds the Android app, the iPhone app, and a web version for quick UI checks. The screens talk to the glasses through one interface, `GlassesService`, so glasses code and screen code meet in one place.

The backend contract the app calls is in [`docs/api.md`](../docs/api.md). The app uses the team's deployed backend (`https://cookalong-backend.onrender.com`) by default; change it under Profile → Developer. Clear the URL to use built-in demo answers instead. When the backend can't answer, the app says "Sorry, I couldn't reach the assistant…" rather than giving a demo answer.

The backend runs on Render's free plan, which sleeps after 15 idle minutes and takes up to a minute to wake. The app wakes it when it opens and when you reach Get ready, so it is usually awake by the first question.

## Run

Needs the Flutter SDK (stable, Dart 3.12 or newer).

```bash
cd mobile
flutter pub get
flutter run -d chrome        # web, simulated glasses only
flutter run                  # a connected Android phone or iPhone
flutter test                 # unit and widget tests
```

Builds need different tools:

| Target | Build on | Also needs |
| --- | --- | --- |
| Web | Windows, macOS or Linux | Chrome |
| Android | Windows, macOS or Linux | Android Studio (Android SDK) |
| iPhone | **macOS only** | Xcode 26.4 or newer, an Apple ID for signing. Apps signed with a free Apple ID stop working after 7 days, so reinstall before a demo. |

To render every screen to PNG for review, see the screenshot section in the UI skill.

## Simulated or real glasses

The app uses the real glasses if it is already registered with the Meta AI app. Otherwise it says "Glasses not connected", and step checks use the phone camera.

Simulated glasses (Meta's Mock Device Kit) are for demos and the web build, and are hidden from users. Turn on **Profile → Developer → Simulated glasses when no real ones** to show them as connected and use their photos. The same section picks the simulated model and simulates a touchpad tap.

### Connect real glasses

Needs the Meta AI app V290 or newer and glasses firmware V128 or newer.

1. In the Meta AI app, open Settings → App Info and tap the version number five times. Turn on **Developer Mode**. If your glasses show an **Install** button there, tap it and keep the app open until it finishes.
2. Install this app on the same phone (see the table above).
3. In this app, open a recipe, tap **Connect** next to the glasses status, then **Connect my glasses**.
4. Meta AI opens. Approve the unverified app; this is normal in Developer Mode. Meta AI returns to CookTogether through the `cookalong://` link.
5. Allow camera access when asked.

If the glasses are turned off later, Get ready shows "Glasses disconnected". Turn them on, tap **Reconnect**, then **Reconnect glasses**.

After that, **Check** on the cooking screen takes a photo with the glasses. The glasses camera turns on only while the photo is taken. If it can't take a photo (glasses folded, too warm, or not connected), the app says why instead of checking a blank image.

Speech and the spoken replies go through the glasses as a normal Bluetooth headset, so they work without this registration.

### Where the setup lives

These are already done. Keep them when you change the app ID or name:

- `ios/Runner/Info.plist`: the `MWDAT` dictionary (Developer Mode values), the `cookalong` URL scheme, accessory and Bluetooth background modes, and local network access.
- `ios/Runner/SceneDelegate.swift`: forwards the Meta AI callback URL to the plugin.
- `android/app/src/main/AndroidManifest.xml`: the Meta app ID and token, plus the `cookalong://` intent filter.
- `android/app/src/main/kotlin/.../MainActivity.kt`: extends `FlutterFragmentActivity`, and `minSdk` is 31.

Both platforms opt out of Meta's toolkit analytics, so study sessions don't send usage data to Meta.

If registration fails with "not set up for Meta glasses", call `MetaWearablesDat.dumpDiagnostics()` from a debug build and fix the findings it lists. The plugin's own guide is [`meta_wearables_dat_flutter`](https://pub.dev/packages/meta_wearables_dat_flutter).
