# Voice feedback checklist

Tester feedback for the next TestFlight build. Work through it in order and tick
each item only once it's verified.

Branch: `going-back`, rebased onto `main`.

## Setup

- [x] Rebase `going-back` onto the latest `main`. 168 tests pass. Main removed the end-of-session summary card, so fixed words now show only in the review sheet.

## Feedback

- [x] **1. The tracker follows going back.** If the reciter pauses and goes back, the place moves back with them. Checked on Tuhfa's real text with a 3-second pause.
- [x] **2. Repeating isn't a mistake.** Repeating the first part of a bayt must not show as a mistake under the second part. The first try counts: a repeat moves the place but never changes a judged word, except a mistake now said right, which becomes fixed (bright yellow highlight; unsure stays gold). A repeat is recognised after 3 words, down from 4. Checked on Tuhfa's real text with scripted repeats; replays unchanged. Each case from before, now:
  - Words already said right stay right when the reciter resumes after a repeat.
  - A repeat of 3 words from further back is a repeat, not added words. A 2-word repeat from further back still shows as added.
  - A misheard word in a repeat isn't a mistake. The phone may still buzz once before the repeat is recognised.
- [ ] **3. Live tracker always shown.** The highlight box stays on the reciter's current word and follows them, in both the poem and prose readers.
- [x] **4. Idgham.** Tanween or noon sakina into ي ر م ل و ن is correct with and without idgham, whichever way Whisper spells it (`Core/Matching/Idgham.swift`). Tested with made-up spellings, not real audio. Needs a real recitation check on a device.
- [ ] **5. Other voice recognition improvements.** Find what else is worth adding, add it, and list each one here.
  - Candidate (from CodeRabbit on #22): a vowel slip said right on a repeat stays a mistake instead of becoming fixed, because repeated words aren't checked for vowels again. It needs the vowel model, which crashes in the Simulator, so it has to be checked on a device.
- [ ] **7. iPhone Duo (foldable).** Built, not yet checked on a Duo:
  - On the open inner screen held sideways, the reader shows two pages in fixed pairs (1–2, 3–4), like a book. Held upright, it shows one page.
  - Landscape only on the Duo, detected by its inner screen being regular in both directions.
  - The reader's page stays the same when the phone folds or opens. For hadith, the hadith and word they were on are kept.
  - Pairing was checked on a Pro Max simulator with `-debugBookView YES`.
  - Still to do: install Xcode 27.1 and check rotation, fold and unfold on the Duo simulator.
- [ ] **6. Ready for TestFlight.** Tests and replays pass, the branch is pushed with a PR open, and the tester knows it's ready.

## Open questions

- The screenshot mentioned in the feedback didn't come through, so item 2 is based on the written description.
- The tester's build may predate the going-back work. Check this when judging item 2.

## Rules

- Never commit audio or transcripts from anyone's recordings.
- Don't merge or upload to TestFlight as part of this work. The tester uploads the build.
