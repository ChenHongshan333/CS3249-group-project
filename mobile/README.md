# CookAlong mobile app (Flutter)

Owners:

- Jaxon: Meta glasses connection (camera, mic, speakers) in `lib/glasses/`
- AI agent (Claude Code): screens converted from the React prototype in `lib/screens/`

One Flutter codebase runs on Android and iPhone. The screens talk to the glasses through one small interface, so glasses code and screen code meet in one place.

The Flutter project has not been created yet. Only one person should run `flutter create` here, so there is a single project.

## Setup

- Flutter SDK, plus Android Studio for Android builds. iPhone builds need a Mac with Xcode.
- Glasses access uses the community plugin [`flutter_meta_wearables_dat`](https://pub.dev/packages/flutter_meta_wearables_dat), which wraps Meta's official Wearables Device Access Toolkit.
- On the demo phone: Meta AI app v254 or newer, glasses firmware v20 or newer, and Developer Mode turned on in the Meta AI app (Settings, App Info, tap the version number five times).

The backend contract the app calls is in [`docs/api.md`](../docs/api.md).
