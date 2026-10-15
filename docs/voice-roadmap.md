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

**Phases B–E are built** (as of 2026-10-12): hardening, mistake detection, flags,
and the Review UX.

**Phase F is built (2026-10-14).** Apple's recognizer didn't recognise Arabic
on the device, so voice review now uses WhisperKit (`WhisperSpeechSource`):

```
SpeechSource (WhisperSpeechSource | MockSpeechSource | SilentSpeechSource)
```

Every `MatchTuning` threshold is still provisional: it was tuned for Apple's
result timing. Next step: `docs/voice-testing.md`.

## Decisions needed first (owner: you)

1. **Mode names.** UX.md says `Memorize | Review`, with Review being the blanked,
   voice-driven page. The code has `Read | Memorize`, with voice inside Memorize.
   Rename to match UX.md (Read→Memorize, Memorize→Review), or update UX.md?
2. ~~**Engine.**~~ Decided: WhisperKit (Apple's recognizer failed on Arabic).
3. **iOS 26 minimum.** PR #1 raised the deployment target from 18 to 26. Your phone
   must be on iOS 26 to install.

## Phase A — Gate: does on-device Arabic work? (ready to run — see `docs/voice-testing.md`)

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
- Confirm the tracker's assumption about results: each `SpeechTranscriber` result covers its
  own audio range, and a volatile result is replaced by the next one for the same range.
  This comes from the API's shape (`range`, `resultsFinalizationTime`) and Apple's sample
  pattern, not from documentation. Log `result.range` with each fragment on the device.
- **Exit:** Arabic transcribes on device, and ≥90% of words reveal on the murattal clip.
  If not, go to Phase F (engine swap) before anything else.

## Phase B — Harden follow-along (bugs found in review, ~1–2 days)

Ordered by severity. Each needs a unit test, and most can use `MockSpeechSource`.

| # | Problem | Fix |
|---|---|---|
| B1 ✅ | Stopping the mic while permission or the model download is pending is ignored; the engine then starts with no owner, so **the mic stays on**. | Keep the start `Task`. In `stop()`, set a `stopRequested` flag and cancel the task; check the flag before `engine.start()`. |
| B2 ✅ | Start errors are swallowed (`try?`): denied permission or an unsupported locale leaves the UI "listening" forever. | Publish a `VoiceStatus` (`idle / preparing / downloading(progress) / listening / failed(reason)`) and reset `isListening` on failure. |
| B3 ✅ | Volatile results repeat the same hypothesis, so two identical consecutive words can be passed on a single utterance. | Track a consumed-token watermark per result (or its audio range); only new tokens advance the cursor. |
| B4 ✅ | One-letter words (و ف ب ل) fuzzy-match any other one-letter word. | Require an exact match below 3 letters. |
| B5 ✅ | "Lost" only triggers when a fragment arrives, so silence never shows it. | Add a session timer that ticks the tracker. |
| B6 ✅ | Swiping or jumping to another page while listening keeps the old cursor. | Reseed the tracker on manual navigation; keep auto-turns separate. |
| B7 ✅ | The page turns only once a word on the *next* page is heard, so that word is never visible being revealed. | Turn when the cursor reaches a page's last word; use the next expected word's page. |
| B8 ✅ | 190 Shatibiyyah words store a `normalized` form that keeps ئ/ؤ; the runtime normalizer folds them to ي/و. This costs one edit of fuzz on every such word. | Build `RecitationIndex` from `ArabicNormalize.normalize(word.text)`, or rebuild the stored forms with the same rules. Add a test that both agree. |

## Phase C — Mistake detection ✅ (first cut)

Done (`RecitationTracker`, `MatchTuning`, `MemorizeWord`):

- The tracker keeps a **committed** state built from final results only and recomputes a
  **tentative** state for each volatile result (which replaces the last one), as
  `SpeechTranscriber` reports results per audio range. Reveal follows volatile text;
  only final text can judge a word, so a corrected partial is never a mistake (fixes B3).
- Outcomes per word: `correct`, `unsure` (fuzzy match or near-miss substitution, amber,
  not a mistake), `wrong(heard:)` (red on a soft red highlight, heard text beneath),
  `skipped` (red highlight, struck through), `unheard` (jumped while re-finding the
  place, or before the first match — secondary ink, not a mistake).
- Words under 3 letters must match exactly (B4). While lost, re-locking needs a word of
  4+ letters or two words in a row. Extra words aren't flagged.
- A haptic on each new mistake; results stay on screen after the mic stops.
- Checked on all three mutun: a perfect recitation gives 0 mistakes in 14,078 words; with
  one word dropped per bayt, all 1,343 drops come back as skips (8 land one word off
  where neighbouring words look alike).

Still to do:

- **Tune `MatchTuning` on a device** with the Phase A clips. Every threshold is provisional.
- `revealed` (help used) arrives with the stuck-word reveal in Phase E.

## Phase D — Flags and persistence ✅

- SwiftData model `Flag { matnID, bayt, half, wordIndex, createdAt, source }`,
  keyed by `(matnID, bayt, half, wordIndex)` so rebuilding the content JSON never orphans flags.
- `wrong`, `skipped` and `revealed` outcomes add a flag. A flagged word recited `correct` in Review removes it.
- Memorize: long-press a word → Flag mistake / Remove flag (light haptic). Draw a red-brown
  pencil underline (`Theme.flag`) in both modes.
- Review: long-press a red word → "Not a mistake".
- This is also where to persist the last page per matn and the Library's "Page N" (UX.md §1–2).

## Phase E — Review mode UX ✅

- Start at the top of the current page; tapping a bayt number starts from that bayt.
- Stuck: tap the next outline to reveal one word, or after about 8 s it fades in (counts as `revealed`).
- Carry on across page turns automatically.
- Stop card: bayts recited, mistakes flagged, then **Review again** / **Back to Memorize**.
- No-voice fallback: the mic shows why it's unavailable (no permission → *Open Settings*;
  model missing → *Download* with size and progress from `AssetInventory`). Tap-to-reveal still works.
- VoiceOver: each bayt is one element, hidden hemistichs read as "hidden", and every gesture has a button or menu.

### How D and E were built (2026-10-12)

- Flags: SwiftData `WordFlag` keyed by `(matnID, bayt, half, wordIndex)`, read through
  `FlagStore`. Wrong, skipped and revealed words gain a flag; a correct recitation or
  **Not a mistake** removes it. Read mode underlines flagged words; long-press a
  half-line to flag or unflag a word. Last page per matn lives in `ReadingPosition`.
- Review: tap a bayt number to recite from it; tap a blank (or wait 8 s) to reveal the
  next word; swiping restarts tracking from that page; the page turns after its last
  word; stopping shows a summary card. Without voice, tapping a blank starts a
  tap-to-reveal sitting, and the footer says why voice is off (with Open Settings).
- Not done: showing the model's download *size* (iOS doesn't expose it before the
  download starts).

## Phase F ✅ — Engine swap to WhisperKit (Phase A failed on device)

- `WhisperSpeechSource` wraps WhisperKit 1.1.1's `AudioStreamTranscriber`.
  `WhisperFragments` maps its state to fragments: each newly confirmed segment
  is final, the unconfirmed text is volatile, and on stop the last guess
  becomes final.
- Models (Settings → Voice model), scored on the 80 s Shatibiyyah clip
  (bayts 1–10), word error rate after `ArabicNormalize`:

  | Model | Size | WER |
  |---|---|---|
  | `openai_whisper-large-v3-v20240930_turbo_632MB` (default) | 632 MB | 13% |
  | `openai_whisper-small_216MB` | 216 MB | 36% |
  | Tarteel's Quran-tuned base (`hrun28/whisperkit-quran`, not shipped) | 160 MB | 51% |

  The Quran-tuned model pulls words toward Qur'anic vocabulary; it is also an
  unofficial conversion with no model card.
- Fed the Turbo transcript, the tracker follows bayts 1–10 to the end with
  3 red words, the rest correct or amber (`WhisperTests`).
- Accuracy and speed (2026-10-14):
  - A heard word can match several written words run together. Shatibiyyah
    writes 117 one-letter prefixes apart (بِـ: بِسْمِ); recited and transcribed
    joined, each used to count as a skip. A whole-text check of all three mutun,
    recited the way Whisper writes them, now gives 0 false mistakes. A word
    heard as two tokens also matches, and a dropped lone letter is amber, not red.
  - Mistakes show from Whisper's current guess once settled (two updates agree,
    or two recited words follow), not only after it finalizes; flags and the
    summary still use finalized results. Segments confirm after 1 newer one.
  - Measured live in the Simulator with two words cut from the clip's audio:
    a skip used to show ~25 s after the next word; now 11–13 s (2 passes). The
    phone's passes should be much shorter; the floor is "the next word is
    heard, plus a pass or two".
- Known limits: WhisperKit's streamer keeps the whole sitting's audio
  (~4 MB a minute) and re-reads it each pass; fine for a page or two, worth
  a rolling buffer if long sittings get slow. Whisper invents text on
  silence; VAD is on to stop that.

## Testing strategy

- Pure logic (tracker, outcomes, reveal, normalizer): Swift Testing, run on every change.
- Fixture regression: `FileSpeechSource` over the recorded clips, asserting
  reveal accuracy and the false-advance rate (device only).
- Data invariant: every hemistich's `words` must match the letter tokens of its `text`
  (a check like this caught 212 bad reveal cuts after PRs #1 and #2 were merged). Add it
  to `Tools/validate_matn.py`.

## Suggested order

A → B1, B2 (mic safety) → B3–B8 → C → D → E. F only if A fails.
