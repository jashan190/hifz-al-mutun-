# Voice features — roadmap

**Date:** 2026-10-11
**Builds on:** `docs/superpowers/specs/2026-10-06-voice-tracking-design.md` (spec) and
`docs/superpowers/plans/2026-10-06-voice-tracking.md` (its 14-task plan, merged as PR #1).
**Target:** the Review mode described in `UX.md` §3.

## Where we are

PR #1 shipped **follow-along**: tap the mic in Memorize mode, recite, and words
reveal as Apple's on-device `SpeechAnalyzer` (iOS 26) hears them. A known-text
cursor (`RecitationTracker`) absorbs recognizer noise. The pieces are isolated:

```
SpeechSource (AppleSpeechSource | FileSpeechSource | MockSpeechSource)
   → RecitationSession → RecitationTracker (pure) → RevealState → PageView
```

Not built yet: mistake detection, flags, persistence, the stuck-word reveal, the
stop card, and the no-voice fallback. **Arabic support on a real device is
still unproven:** the GATE spike (`FileTranscriptionSpikeTests`) has never run
on a phone.

## Decisions needed first (owner: you)

1. **Mode names.** UX.md says `Memorize | Review`, with Review being the blanked,
   voice-driven page. The code has `Read | Memorize`, with voice inside Memorize.
   Rename to match UX.md (Read→Memorize, Memorize→Review), or update UX.md?
2. **Engine.** UX.md specifies WhisperKit. PR #1 chose Apple `SpeechAnalyzer`
   (no download, streaming partials) behind the `SpeechSource` protocol.
   Recommendation: keep Apple if Phase A passes, and fall back to WhisperKit only if it fails.
3. **iOS 26 minimum.** PR #1 raised the deployment target from 18 to 26. Your phone
   must be on iOS 26 to install.

## Phase A — Gate: does on-device Arabic work? (do first, ~½ day)

- Install the iOS 26.2 platform in Xcode (Settings → Components) and run
  `HifzAlMutunTests` on the phone.
- Make the gate honest: `transcribesArabicClip` currently *passes* when no
  locales are supported. Skip only on the Simulator (`#if targetEnvironment(simulator)`);
  on a device, an empty list or missing Arabic must **fail**.
- Locale: `SpeechModel.ensureInstalled` compares full BCP 47 identifiers, so
  the requested `"ar"` never matches a supported regional locale such as
  `ar-SA` and it throws `localeUnsupported`, which `RecitationSession.start()`
  then discards with `try?` (see B2). Match on the language code and pick a
  supported regional locale *before* creating the `SpeechTranscriber`.
- Record 3 fixture clips (murattal, melodic, fast drill) for one page each, and
  measure reveal accuracy with `FileSpeechSource` → tracker.
- **Exit:** Arabic transcribes on device, and ≥90% of words reveal on the murattal clip.
  If not, go to Phase F (engine swap) before anything else.

## Phase B — Harden follow-along (bugs found in review, ~1–2 days)

Ordered by severity. Each needs a unit test, and most can use `MockSpeechSource`.

| # | Problem | Fix |
|---|---|---|
| B1 | Stopping the mic while permission or the model download is pending is ignored; the engine then starts with no owner, so **the mic stays on**. | Keep the start `Task`. In `stop()`, set a `stopRequested` flag and cancel the task; check the flag before `engine.start()`. |
| B2 | Start errors are swallowed (`try?`): denied permission or an unsupported locale leaves the UI "listening" forever. | Publish a `VoiceStatus` (`idle / preparing / downloading(progress) / listening / failed(reason)`) and reset `isListening` on failure. |
| B3 | Volatile results repeat the same hypothesis, so two identical consecutive words can be passed on a single utterance. | Track a consumed-token watermark per result (or its audio range); only new tokens advance the cursor. |
| B4 | One-letter words (و ف ب ل) fuzzy-match any other one-letter word. | Require an exact match below 3 letters. |
| B5 | "Lost" only triggers when a fragment arrives, so silence never shows it. | Add a session timer that ticks the tracker. |
| B6 | Swiping or jumping to another page while listening keeps the old cursor. | Reseed the tracker on manual navigation; keep auto-turns separate. |
| B7 | The page turns only once a word on the *next* page is heard, so that word is never visible being revealed. | Turn when the cursor reaches a page's last word; use the next expected word's page. |
| B8 | 190 Shatibiyyah words store a `normalized` form that keeps ئ/ؤ; the runtime normalizer folds them to ي/و. This costs one edit of fuzz on every such word. | Build `RecitationIndex` from `ArabicNormalize.normalize(word.text)`, or rebuild the stored forms with the same rules. Add a test that both agree. |

## Phase C — Mistake detection (~2–3 days)

The tracker currently only moves a cursor. Make it emit **per-word outcomes**:

- `correct` (exact or within threshold), `unsure` (borderline distance, shown amber and not flagged),
  `wrong(heard:)` (the expected word in red, the heard word in small type beneath),
  `skipped` (passed over by a skip, shown red and struck through), `revealed` (help used, secondary ink).
- Store the outcomes in a `[wordIndex: WordOutcome]` map in the session; `RevealState`
  then carries a style per word, not just a count.
- Tune the thresholds against the Phase A fixtures. Chanting stretches vowels,
  so normalized forms already ignore them. Add a short-word rule (B4) and a
  confidence cut for `unsure`.
- Unit-test with scripted fragments for each outcome.

## Phase D — Flags and persistence (~2 days)

- SwiftData model `Flag { matnID, bayt, half, wordIndex, createdAt, source }`,
  keyed by `(matnID, bayt, half, wordIndex)` so rebuilding the content JSON never orphans flags.
- `wrong`, `skipped` and `revealed` outcomes add a flag. A flagged word recited `correct` in Review removes it.
- Memorize: long-press a word → Flag mistake / Remove flag (light haptic). Draw a red-brown
  pencil underline (`Theme.flag`) in both modes.
- Review: long-press a red word → "Not a mistake".
- This is also where to persist the last page per matn and the Library's "Page N" (UX.md §1–2).

## Phase E — Review mode UX (~2–3 days)

- Start at the top of the current page; tapping a bayt number starts from that bayt.
- Stuck: tap the next outline to reveal one word, or after about 8 s it fades in (counts as `revealed`).
- Carry on across page turns automatically.
- Stop card: bayts recited, mistakes flagged, then **Review again** / **Back to Memorize**.
- No-voice fallback: the mic shows why it's unavailable (no permission → *Open Settings*;
  model missing → *Download* with size and progress from `AssetInventory`). Tap-to-reveal still works.
- VoiceOver: each bayt is one element, hidden hemistichs read as "hidden", and every gesture has a button or menu.

## Phase F — Engine fallback (only if Phase A fails)

- `WhisperKitSource: SpeechSource`. Use a small Arabic-capable model, downloaded in the app
  with progress, and a streaming loop over about 1 s windows.
- The tracker and UI stay unchanged. Re-run the Phase A fixtures to compare engines.

## Testing strategy

- Pure logic (tracker, outcomes, reveal, normalizer): Swift Testing, run on every change.
- Fixture regression: `FileSpeechSource` over the recorded clips, asserting
  reveal accuracy and the false-advance rate (device only).
- Data invariant: every hemistich's `words` must match the letter tokens of its `text`
  (a check like this caught 212 bad reveal cuts after PRs #1 and #2 were merged). Add it
  to `Tools/validate_matn.py`.

## Suggested order

A → B1, B2 (mic safety) → B3–B8 → C → D → E. F only if A fails.
