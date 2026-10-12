# Voice Tracking (Memorize mode) — Design

**Date:** 2026-10-06
**Status:** Draft for review
**Feature branch:** TBD (currently on `connecting-noons`; this work gets its own branch)

## Summary

Let a user recite a matn aloud and have the app follow along, revealing the
poem word-by-word in Memorize mode as each word is correctly recited. The app
keeps its place in a known text even when the speech recognizer mishears the
audio, and it degrades gracefully (pauses, re-locks) rather than breaking.

Mistake detection is **explicitly out of scope** for this version; the design
leaves a clean seam for it later.

## The core reframing

This is **not** open-ended transcription. We already know the exact word
sequence of every matn. So the problem is not "what did the user say?" but
"given that they are reciting *this known poem*, where are they now?" — an
alignment/tracking problem, not a dictation problem.

Consequence: we treat the speech recognizer's output as a **noisy hint**, not
ground truth. A position cursor walks forward through the known words and
advances when the incoming audio lines up "well enough." Word-level reveal is
then just "render up to the cursor." The precision comes from the known text,
not from flawless hearing. This is what makes the feature survive melodic
chanting, where no recognizer transcribes drawn-out vowels reliably.

## Scope

**In (this version):**
- Live follow-along in Memorize mode: tap mic → recite → words reveal.
- Word-by-word reveal (see "Feedback model").
- Auto page-turn when the last word on a page is revealed.
- Graceful "lost / listening…" state with automatic re-sync.
- Starts from the first bayt on the page currently open (user recites from
  where they are looking, not from the poem's start).
- On-device only. Microphone + speech-recognition permissions handled.

**Out (deferred):**
- Mistake flagging, correction, or scoring.
- Saving or exporting recordings.
- Any cloud/network processing.
- Jumping to arbitrary positions by voice command.

## Recitation styles to tolerate

Target users recite in a **mix** of styles — melodic chanting, plain reading
pace (murattal), and fast memorization drills. The matching approach must not
assume any one style. This is why the design leans entirely on the known-text
cursor rather than recognizer accuracy.

## Architecture: three isolated components

### 1. `SpeechSource` (protocol) + `AppleSpeechSource`

Turns audio into a stream of recognized text fragments.

- Protocol so the engine is swappable (decision: start with Apple, keep the
  door open for WhisperKit later without touching the tracker or UI).
- `AppleSpeechSource` wraps iOS 26's on-device `SpeechAnalyzer` /
  `SpeechTranscriber` for Arabic (`ar-SA` / `ar`). Chosen for **low-latency
  streaming partial results** (needed for responsive reveal) and no model
  download — raw accuracy on classical Arabic is rough, but the known-text
  matcher absorbs that.
- `FileSpeechSource` feeds a recording file through the same interface. This is
  how we test with YouTube fixture audio and how we exercise the pipeline in
  the simulator (which has no useful live mic).

Emits: a sequence of `(text, isFinal)` fragments, where `text` is the
recognizer's current hypothesis and `isFinal` marks a stabilized segment.

**Dependencies:** `Speech` framework, `AVAudioEngine` for mic capture.

### 2. `RecitationTracker` (pure logic)

The brain. No audio, no UI → fully unit-testable.

**Holds:**
- The expected normalized-word sequence for the current matn (built from the
  `Word.normalized` values already in the content model — harakat stripped,
  alif unified, `ى→ي`, `ة→ه`).
- A position cursor (index into the word sequence).
- A confidence / lock state: `locked` vs `lost`.

**Inputs:** text fragments from a `SpeechSource` (normalized the same way).

**Outputs:** current word index (what to reveal up to) + lock state, published
for the UI to observe.

**Matching rules (the heart of it):**
- **Forward window.** For each incoming fragment, only consider the next ~N
  expected words from the cursor (N ≈ 12, tunable). Find the best alignment in
  that window; advance the cursor past matched words.
- **Forward-only within a lock.** The cursor never steps backward on a single
  noisy fragment, so a drawn-out chanted vowel can't make the reveal flicker
  or un-reveal a word.
- **Skip tolerance.** If the recognizer drops a word (common with elongation),
  a strong match on a *later* window word lets the cursor step over the gap
  (bounded, e.g. skip at most 1–2 unmatched expected words).
- **Fuzzy, not exact.** Normalized equality first; then a small edit-distance
  threshold for near-misses.
- **Lost → re-sync.** If nothing matches for a short interval (~2 s), enter
  `lost`: widen the search window and attempt to re-lock. Handles pauses,
  phone-across-the-room, and the user restarting a line.

**Dependencies:** none beyond Foundation and the content model's words.

### 3. Reader binding (UI)

- `RecitationTracker` publishes `currentWordIndex` + lock state.
- `PageView` / `BaytRow` render Memorize mode from that index (see below).
- Auto page-turn: when `currentWordIndex` crosses onto the next page, advance
  `PageScreen.currentPage` with the existing smooth transition.
- `MicButton` already owns the `isListening` toggle; wiring it starts/stops the
  `SpeechSource` and resets the tracker's cursor to the current page's first
  bayt.

## Feedback model (reveal, not highlight)

Memorize mode today blanks each hemistich to a single faint 2 pt line
(`PageView.swift:238`), deliberately hiding word count and word lengths. The
voice feature *drives the reveal* of that blank.

**Decision: single blank remainder** (not per-word placeholders). Rationale:
the point of Memorize mode is recall; per-word placeholders would leak word
count and relative lengths as hints, undermining the test. The revealed words
accumulating from the right already give a sense of progress, and the page
filling in is its own progress meter.

States:
- **Memorize + mic off:** the blank line exactly as today — manual recall
  practice, unchanged.
- **Memorize + listening:** the hemistich starts blank; each correctly-recited
  word appears at its natural size from the **right** (RTL), the remaining
  blank shrinking leftward. The word's real colors (black / blue / red) are
  present the instant it appears — we reveal the actual text, so no recoloring.
- **Reveal frontier cue:** a subtle anchor where the next word will appear, so
  the eye knows where to look.
- **Lost / re-sync:** reveal pauses — nothing already shown disappears — and a
  quiet "listening…" cue sits near the mic until the tracker re-locks.
- **Page turn:** when the last word on the page is revealed, the page turns.

**Implementation note:** revealing "word k" means showing the segments up to
the end of word k. The content stores `segments` (for display) and `words`
(for matching) separately, and a colored segment can be a single letter inside
a word (farsh rumūz). So we need a **word → segment-range mapping** within each
hemistich. This mapping is required regardless of reveal style and is a small,
testable pure function built from the existing per-hemistich data.

## Testing strategy

- **Tracker unit tests (no audio).** Feed synthetic fragment streams and assert
  the cursor path: perfect recitation, dropped words, misheard words, a
  mid-line restart, silence/pause then resume. This is where correctness is
  proven, independent of any recognizer.
- **Word→segment mapping unit tests.** Verify reveal boundaries, including a
  hemistich where a colored segment splits a word.
- **Engine integration (fixtures).** Pull 1–2 full Shatibiyyah recitations from
  YouTube as fixture audio, run them through `FileSpeechSource` →
  `RecitationTracker`, and measure how closely the cursor path follows the real
  recitation. This empirically answers whether Apple's engine is good enough or
  whether WhisperKit is warranted.
- Per the user's working style: build + run in the simulator after each step.

## Risks & gates

1. **Apple Arabic on-device availability (go/no-go gate).** The **first
   implementation milestone is a spike**: confirm the `ar` / `ar-SA`
   on-device transcription asset installs and streams on-device under iOS 26's
   `SpeechTranscriber`. If it is unavailable or network-bound, we revisit the
   engine choice (WhisperKit) before building on top.
2. **Word-level precision during melodic chanting.** May in practice settle at
   bayt-granularity for heavily melodic recitation. The design degrades
   gracefully to that (the reveal simply advances in bursts) rather than
   breaking.
3. **Simulator microphone.** Live mic in the simulator is unreliable; the
   `FileSpeechSource` path is the primary dev/test loop, with on-device runs
   for real-mic validation.

## Permissions & housekeeping

- `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` in
  Info.plist (via `project.yml`).
- Permissions requested on first mic tap, with a graceful denial path (a quiet
  explanatory state, mic returns to idle).
- All processing on-device; nothing leaves the phone.

## Seam left for mistake detection (future)

The tracker already compares "expected word" against "what was heard." A later
layer can observe a mismatch (substitution, skip, or stall on a word) and
surface it without changing the tracking core — a natural extension point, not
built now.

## Phased delivery (high level; detailed plan comes next)

1. Spike: Apple Arabic on-device transcription proof (gate).
2. `SpeechSource` protocol + `FileSpeechSource` + fixture harness.
3. `RecitationTracker` with unit tests (synthetic streams).
4. Word → segment-range mapping + reveal rendering in Memorize mode.
5. `AppleSpeechSource` (live mic) + permissions, wired to `MicButton`.
6. Auto page-turn, lost/re-sync UI polish, fixture-based accuracy pass.
