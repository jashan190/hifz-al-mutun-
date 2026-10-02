# UX.md — Hifz al-Mutun (simplified)

Read SPEC.md and this file before any UI work. This file replaces every UX part of SPEC.md.

The app does three things: it shows each matn exactly like the printed page, it lets me read it, and it lets me recite to it on a hidden page while it marks my mistakes. Everything else in SPEC.md (daily sittings, the review rotation, progress screens, a mistakes list, listen-and-loop audio, onboarding) is out of scope for now: don't build it. If some of it already exists, list it and ask me before removing or hiding it.

## HOW TO WORK
1. Audit what exists against this file. Give me a short table (part | exists | missing or different) and wait for my go-ahead.
2. Build in the order below. For each part: SwiftUI previews in light and dark and at the largest Dynamic Type size, a clean build, then stop for me to test on my phone.

## 1. LIBRARY (home screen)
- A NavigationStack titled "Mutun": the mutun in study order (Tuhfat al-Atfal, al-Jazariyyah, ash-Shatibiyyah). The list comes from the content JSON, so a new matn is added by dropping in its file.
- Each row: the Arabic title, the transliteration beneath, the number of bayts, and "Page N" if I've opened it before.
- Tapping a matn opens it at the last page I was on.

## 2. THE PAGE (the core of the app)
- It mirrors my PDF: the same bayts on the same page in the same order, each bayt a row of two hemistichs right to left (sadr on the right, ajuz on the left), bayt numbers in Eastern Arabic numerals, Amiri with full harakat.
- Paged, one page per screen, fitted to the width. Swipe right for the next page, like an Arabic book. Slide animation; none with Reduce Motion.
- Every word is its own view, so it can be shown, hidden, revealed or flagged without the page reflowing.
- Top bar: back to the Library, the matn title, the current bab and page number, and an index button. Tapping the empty margin hides and shows the bars.
- The index button opens a sheet listing the abwab with their page numbers, plus Go to page.
- Remember the last page for each matn.
- Larger text with Dynamic Type keeps every bayt on its row and page; the page grows taller and scrolls within itself.
- Light and dark follow the system.

## 3. THE FOOTER: TWO MODES
- A segmented control pinned at the bottom of the page: Memorize | Review. Memorize is the default each time I open a matn.

### Memorize mode
- The full text, with my flagged words underlined.
- Long-press a word: Flag mistake, or Remove flag. A light haptic when a flag is set.
- Nothing else.

### Review mode
- The page is blanked: a faint outline where each hemistich sits. No letters, no word lengths. Bayt numbers stay visible.
- Reviewing starts at the top of the current page; tapping a bayt number starts from that bayt instead.
- A mic button in the footer, beside the segmented control: tap to start reciting, tap again to stop.
- As I recite, each matched word appears in its place in normal ink.
- Mistakes:
  - A wrong word: the expected word appears in red, with what I said in small type beneath it.
  - A skipped word: appears in red, struck through.
  - Both are flagged on that word.
  - A low-confidence match: amber, not flagged.
- Stuck: tap the next outline to reveal the next word, or wait about 8 seconds and it fades in. A revealed word shows in the secondary ink and is flagged.
- Long-press a red word: "Not a mistake" removes the flag, because voice recognition can be wrong.
- At the end of a page, turn to the next page automatically and carry on.
- Stop shows a small card: bayts recited and mistakes flagged, with Review again and Back to Memorize (where the new flags now show).
- Without voice: if the voice model isn't downloaded or microphone permission is off, the mic button says why and offers Download (with its size and progress) or Open Settings. Review still works meanwhile: tap each outline to reveal the next word, and long-press to flag.
- The voice engine is as described in SPEC.md: WhisperKit on-device, with the matching layer under the display.

## FLAGS
- One kind of mark: a pencil-like underline in a warm red-brown under the flagged word or words. The same mark whether it came from voice, a reveal, or my long-press.
- Flags persist and show in both modes.
- A flagged word that I later recite correctly in Review loses its flag.

## DESIGN
- The page is the screen: keep the bars thin and out of the way, with 16-point margins.
- The system font for the UI; Amiri only on the page.
- Colour tokens with light / dark values:
  - page: #FBF8F1 / #141413
  - ink: #1D1B18 / #E9E5DD
  - inkSecondary (revealed hints): ink at 45%
  - outline (hidden hemistichs): ink at 12%
  - accent (mic button, selected segment): #1E5B3A / #5FB585  (Madinah green; also the app's AccentColor)
  - flag: #B4532A / #E08A5F
  - error: #C62828 / #EF6B6B
  - unsure: #B7860B / #E0B341
  Check every pairing for at least 4.5:1 contrast and adjust if needed.
- Right to left: flip the swipe direction and anything meaning next or previous. Don't flip numerals or the mic icon.
- VoiceOver: each bayt is one element; hidden hemistichs read as "hidden"; every gesture also has a menu or button.
