# Testing CookAlong on an Android phone with the glasses

This guide is for testing the app on a real Android phone with our Meta glasses. Set aside about an hour for setup the first time, and 30 minutes for the tests. Fill in the results table as you go and send it back. Notes like "it said X" or "nothing happened" are just as useful as Pass or Fail.

## What you need

- An Android phone with **Android 12 or newer**, and its USB cable
- The Meta glasses (Meta Nova), charged
- A Windows, macOS or Linux computer with about 15 GB free
- Nothing else: the app already points at our backend, `https://cookalong-backend.onrender.com`

## 1. Set up the computer

1. Install **Flutter**, the stable version, from https://docs.flutter.dev/get-started/install. Put it in a folder **without spaces** in the path. If your system drive is nearly full, it can go on another drive.
2. Install **Android Studio**. During setup, let it install the Android SDK and platform tools.
3. In a terminal, run `flutter doctor --android-licenses` and accept them. Then run `flutter doctor`. The Flutter and Android toolchain lines must show ✓.
4. Get the code:
   ```bash
   git clone https://github.com/ChenHongshan333/CS3249-group-project.git
   cd CS3249-group-project
   git checkout main && git pull
   ```

## 2. Set up the phone

1. **Developer options**: Settings → About phone → tap **Build number** 7 times. Then, in Developer options, turn on **USB debugging**.
2. Connect the phone with the USB cable. On the phone, allow USB debugging for this computer.
3. On the computer, run `flutter devices`. Your phone should be in the list.
4. **Meta AI app**:
   - Install it and sign in. The glasses can only be paired with one phone at a time, so ask Hongshan to unpair them first.
   - Check that the app is **V290 or newer** and the glasses firmware is **V128 or newer**.
   - Pair the glasses.
   - Go to Settings → App Info, tap the version number 5 times, and turn on **Developer Mode**.
   - If the glasses show an **Install** button there, tap it. Keep the app open until it finishes.

## 3. Run the app

```bash
cd mobile
flutter pub get
flutter run
```

The first build takes several minutes. Keep the terminal open while you test: errors show up there.

Then:

1. **Wake the backend first.** It sleeps after 15 idle minutes. In the phone's browser, open https://cookalong-backend.onrender.com/health and wait until it shows `"configured": true`, which can take up to a minute. If it shows `false`, tell Hongshan.
2. The app already uses this backend; you don't need to enter it. You can check under **Profile → Developer → Backend URL**.

## 4. Tests

Write **Pass**, **Fail**, or what happened.

| # | Do this | Expect | Result |
| --- | --- | --- | --- |
| **Glasses** | | | |
| G1 | Choose a recipe → on **Get ready**, tap **Connect** next to the glasses → **Connect my glasses** | Meta AI opens and asks you to approve an unverified app | |
| G2 | Approve in Meta AI | You're back in CookAlong; the sheet says "Connected to …" with a battery level | |
| G3 | Close the app fully and reopen it | It reconnects to the real glasses by itself, not the "Mock Kit" | |
| G4 | Turn the glasses off → on **Get ready**, check the status. Turn them on → **Reconnect** → **Reconnect glasses** | "Glasses disconnected", then "Connected to …". No simulated glasses are offered | |
| **Opening chat** | | | |
| O1 | On Get ready, leave **two ingredients unticked** → **Start cooking** | You hear "Today we're making …, right? Have you got the …?" naming those two | |
| O2 | Say "I don't have *(one of them)*" | A short, sensible reply (it works without it, or a swap) | |
| O3 | Say "I've got the *(other one)*" | It gets ticked on screen | |
| O4 | Say "Let's start" | Step 1 is read out | |
| O5 | Before saying "let's start", suggest your own swap, e.g. "Could I use lemon instead of some of the oil?" | One sentence on whether it is healthier and fits the dish. If it is, it says which step it changed and "Changed for you" appears in the chat | |
| **Voice through the glasses** | | | |
| V1 | Wear the glasses; say "next step" | The app moves on. Note whether the glasses mic or the phone mic heard you | |
| V2 | Listen to a step being read | Note whether the sound comes from the glasses or the phone | |
| V3 | While it is talking, say "hold on" (also try "wait" and "stop") | It stops talking at once and listens. Note whether the phone beeps while it talks, and whether it ever stops by itself without you speaking. If the beeps are annoying, turn off **Profile → Say "hold on" to interrupt** | |
| **Questions and offers** | | | |
| Q1 | On a step, ask "How small should the pieces be?" | One or two sentences about this step, not a demo answer | |
| Q2 | On a step with waiting time, ask "How long does this take?" | It answers and asks "Would you like a … timer?" | |
| Q3 | Say "Yes please" | A timer appears on screen and counts down | |
| Q4 | Say "set a timer for 4 minutes", and let it run | A short sound when it starts; spoken reminders at 2 minutes and 1 minute left; a ding and "…timer just finished" at the end; the timer row disappears by itself a few seconds later. Note whether the sounds cut off speech or listening | |
| **Photo check** | | | |
| P1 | Point at the food → tap **Check** (or say "check this") | The glasses take a photo (capture light comes on briefly), then a reply that describes what's in front of you | |
| P2 | Fold the glasses → **Check** | It says to unfold them. It does not give a food verdict | |
| P3 | Photograph something unrelated (a wall) → **Check** | It says it can't see the food clearly and suggests what to change | |
| P4 | If you cook meat: cut it open → ask "Is it cooked?" | It describes what it sees and says a photo can't confirm it is cooked. It never says it's safe | |
| P5 | Turn the glasses off → **Check** | It says the glasses couldn't take the photo, then the phone camera opens. Take a photo: you get a reply about it | |
| P6 | **Check**, then close the phone camera without taking a photo | It says no photo was taken. Nothing is sent to the AI | |
| P7 | On **Get ready**, tap **Test camera**. Then fold the glasses and tap **Try again** | The glasses photo is shown with "Your camera works". Folded, it says to unfold them and that the phone camera will be used instead | |
| **Finish** | | | |
| F1 | Finish a recipe → **Take a photo of your dish** → **With my glasses**. Then **Retake photo** → **With my phone** | Each photo shows on the Finish screen. Under **History**, the meal shows the last photo instead of the emoji, also after closing and reopening the app | |
| **Timing** | | | |
| T1 | Note roughly how long Q1 and P1 take from asking to hearing the answer | Under 6 s and 8 s | |

## 5. Send back

- The filled table
- Your phone model and Android version, the Meta AI app version, and the glasses firmware version
- For anything that failed: a screenshot, and the error text from the `flutter run` terminal

## If something goes wrong

| Problem | Try |
| --- | --- |
| Phone not in `flutter devices` | Set USB mode to "File transfer", unplug and replug the cable, and allow debugging on the phone |
| Build fails with "out of memory", or `hs_err_pid*.log` files appear | Close other programs and run `flutter run` again. Don't commit those log files |
| "This build is not set up for Meta glasses" | Check that Developer Mode is on in Meta AI and that **Install** was done, then tell Hongshan |
| "No glasses found" | Open Meta AI and check the glasses are connected there. Then try **Connect my glasses** again |
| "Sorry, I couldn't reach the assistant" | The backend is down or the phone is offline. Open `/health` from step 3. If it loads, ask again |
| "The assistant took too long to answer" | The backend was probably asleep. Wait a few seconds and ask again |
| Answers sound generic or mention "demo" | The Backend URL under Profile → Developer is empty. Put back `https://cookalong-backend.onrender.com` |
