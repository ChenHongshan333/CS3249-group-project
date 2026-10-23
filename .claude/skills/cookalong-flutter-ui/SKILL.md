---
name: cookalong-flutter-ui
description: Design rules and review workflow for the CookAlong (CookTogether) Flutter app in mobile/. Use when creating, restyling, or reviewing any screen, widget, theme token, or copy under mobile/lib/, or when someone says the UI feels cluttered, text-heavy, or lacks focus.
---

# CookAlong Flutter UI

Adapted for this project from Anthropic's `frontend-design` skill (aesthetic
direction, plan → build → critique) and the community `flutter-ui-design`
skill (semantic tokens first, one primary action per surface, rendered
verification).

## Who uses this and where

- Beginner cooks, hands busy or wet, phone propped on the counter about an
  arm's length away, often wearing Meta glasses.
- The app is voice-first. The screen is a glanceable backup, not something
  to read. If a sentence is also spoken, it does not need to be on screen too.
- Every screen answers one question. Before you build, write it down:

| Screen | The one question | Primary action |
| --- | --- | --- |
| Home | What do I do now? | Choose a recipe |
| Recipes | What shall I cook? | Tap a recipe |
| Prep | Am I ready? | Start cooking |
| Cooking | What do I do in this step? | Next step (or say it) |
| Finish | Did I do it? | Done |
| History | What have I made? | (browse) |
| Profile | How should CookAlong behave? | Save |

## Design direction: "a recipe card on the counter"

Warm paper background, dark ink, generous space, one accent. It should feel
calm and confident, not like a dashboard.

- **Accent (terracotta)** is only for the primary action and the active
  nav item. If two terracotta things are on screen, one is wrong.
- **Green** only means "done / selected / ready". Never decoration.
- **Amber** only means "timer / needs attention".
- No gradients, rotated pills, decorative glyphs (✦ ✳), orbit rings, or
  drop shadows for decoration. Elevation only for things that float
  (bottom sheets, toasts, the sticky action bar).

## Tokens (mobile/lib/theme/app_theme.dart)

Always use `CookTogetherTheme` tokens and the text styles from
`Theme.of(context).textTheme`. Never hard-code a `Color(0xFF...)` or a
`fontSize` in a screen. If you need a new one, add a token first.

| Role | Token |
| --- | --- |
| Page background | `background` |
| Raised surface (cards, sheets) | `surface` |
| Hairline | `line` |
| Main text | `ink` |
| Secondary text (passes WCAG AA on `background`) | `inkMuted` |
| Primary action | `accent` / `onAccent` |
| Done / selected | `success` (text and fills), `successSoft` (backgrounds) |
| Timer / attention | `warning`, `warningSoft` |

Type scale (system font: Roboto on Android, SF on iOS; no custom fonts):

| Style | Size / weight | Use |
| --- | --- | --- |
| `displaySmall` | 30 / w800 | One hero line per screen at most |
| `headlineSmall` | 24 / w800 | Current step title |
| `titleLarge` | 20 / w700 | Step instruction, sheet titles |
| `titleMedium` | 17 / w700 | List item titles, header titles |
| `bodyLarge` | 16 / w400 | Body text, chat messages |
| `bodyMedium` | 14 / w400 | Secondary lines, muted |
| `labelLarge` | 15 / w700 | Buttons |

**Nothing smaller than 13 px.** Uppercase letter-spaced "eyebrow" labels are
banned. Use plain sentence case.

Spacing: 4, 8, 12, 16, 24, 32. Screen side padding is 20. Radius: 12
(controls), 16 (cards and tiles), 28 (sheets).

## Shared widgets (mobile/lib/theme/widgets.dart)

Reuse these before writing a new container:

- `ScreenHeader`: back button plus title. No eyebrow, no decoration.
- `PrimaryButton`: full width, 56 tall, the only accent button on a screen.
- `BottomActionBar`: sticky footer holding the primary button and an
  optional one-line hint.
- `EmojiTile`: recipe emoji on a soft tone square.
- `CheckRow`: large tappable checklist row.
- `StatusDot`: small coloured dot with a short label, for connection states.

## Rules

1. **One primary action per screen**, placed where the thumb is: the bottom
   action bar. Secondary actions are text buttons or icons with tooltips.
2. **Cut the copy.** Each piece of text does one job. Remove subtitles that
   restate the title, marketing lines, and notes the user has already seen.
   Keep safety copy, but say it once, short, in the place it applies
   (for example under a camera check, not on every screen).
3. **Group with space, not boxes.** A screen should have at most two
   bordered cards. Prefer section titles plus whitespace or dividers.
4. **Touch targets ≥ 48×48.** Cooking-screen controls ≥ 56.
5. **Glanceable cooking screen.** Hierarchy is: step title → instruction →
   (timer) → everything else. The conversation is secondary and visually
   quieter. Step announcements that duplicate the step card are not repeated
   as chat bubbles.
6. **Developer and demo controls stay out of the main flow.** Mock Device
   Kit model switching, touchpad simulation, and the server URL go behind a
   "Change" link, a sheet, or a "Developer" section.
7. **States are explicit**: empty, disabled (say why, in one line),
   loading/listening/thinking, done. Each state has at most one next action.
8. **Icons that aren't obvious get a label or a tooltip.**
9. Keep accessibility: `Semantics` or `tooltip` on icon-only buttons,
   contrast ≥ 4.5:1 for text, and no information carried by colour alone.

## Clichés to avoid

Eyebrow labels, middle-dot metadata strings longer than 3 items, two-tone
headlines ("Hands-free cooking, *step by step.*"), every group in an
identical rounded card, decorative emoji in headings, gradient hero cards,
and an "AI" sparkle icon on every message.

## Workflow

1. Read the screen and write its one question and primary action (table above).
2. List what to cut, merge, or demote before adding anything.
3. Build with tokens, the text theme, and shared widgets.
4. Render and look at it:

   ```bash
   cd mobile
   SCREENSHOT_DIR=../build/screens flutter test test/screenshot_test.dart
   ```

   In PowerShell: `$env:SCREENSHOT_DIR='..\build\screens'; flutter test test/screenshot_test.dart`.
   This writes one PNG per screen at 402×874 (iPhone 17 logical size), and
   fails on any overflow. Open the PNGs and critique them against the rules.
   Count primary-coloured elements and bordered cards, and look for text
   under 13 px.
5. Run `flutter analyze` and `flutter test`. Both must be clean.
6. Report concrete changes, such as "removed 4 cards", "Next step is now a
   56 px button", or "min text 13 px", not adjectives.
