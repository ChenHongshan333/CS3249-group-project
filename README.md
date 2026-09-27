# CookAlong interactive prototype

A mobile-first React prototype for CS3249, based primarily on the hand-drawn low-fidelity screens. The Figma workflow informs the order and branches; the four-color palette comes from the supplied reference image.

## Run

```bash
npm install
npm start
```

Open the URL printed by Vite. On desktop, the interface is framed at the iPhone 17's 402 × 874 CSS-pixel viewport. On a phone it fills the viewport.

## Demo path

1. Dismiss the AI introduction. Optionally edit Preferences.
2. Select a recipe, then choose **solo**, **same kitchen**, or **online with a friend**.
3. For a paired mode, tap **Simulate friend joining**. Check ingredients and start.
4. Use Repeat, Pause, Ask, the text or voice input, timer, audio/video toggles, and the simulated camera check. Complete each step.
5. View the meal in History. On the completion screen, export a short animated WebM recap. This video contains no camera footage.

Everything runs in the browser. Pairing, partner camera, visual checks, conversation replies, community posts, and recipe-video import are demo states rather than live services. The browser's speech synthesis and speech recognition are used when available. History, preferences, and community posts persist in localStorage.

The simulated camera check deliberately does not claim to verify doneness or allergy safety. The UI asks users to check those themselves.
