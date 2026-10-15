# Testing voice on your iPhone

Voice review listens with Whisper (WhisperKit), on the phone. The model downloads
once, the first time you tap the mic (632 MB for Turbo, the default; 216 MB for
Small, under **Library → Settings → Voice model**), so be on Wi-Fi. It also runs
in the Simulator, using the Mac's microphone. Everything else (the reveal,
mistakes, flags, page turns, the summary) can be scripted in the Simulator with
the debug launch arguments at the end.

## One-time setup

1. iPhone on **iOS 26 or later**, connected by cable (or on the same Wi-Fi after
   the first cable run).
2. On the phone: **Settings → Privacy & Security → Developer Mode → On** (it restarts).
3. Signing: `Config/Local.xcconfig` (git-ignored) holds this Mac's team and bundle
   id. On another Mac, copy `Config/Local.xcconfig.example` and fill it in.
4. `xcodegen generate && open HifzAlMutun.xcodeproj`, pick the iPhone in the device
   menu, press **⌘R**. The first run creates a development certificate; on the phone,
   trust it under **Settings → General → VPN & Device Management**.

## Step 1 — first start

Open a matn, switch to **Memorize**, tap the mic. The footer shows, in order:
1. the microphone prompt (allow it);
2. "Downloading Arabic voice N% (once)" — a few minutes on Wi-Fi;
3. "Preparing Arabic voice… the first time takes a minute." — iOS compiles the
   model for this phone. Later starts take a few seconds (again after an iOS update).

Then recite. Words appear about a second after you say them: Whisper listens in
one-second steps.

Optional: the same check as the Mac ran on the bundled clip, on the phone —
**Product → Scheme → Edit Scheme → Test → Arguments → Environment Variables**,
add `WHISPER_E2E` = `1`, then **⌘U**. `transcribesTheClip` prints `WHISPER clip:`
and the transcript.

## Step 2 — recite

Try each of these and note what happens:

| Try | Expect |
|---|---|
| Recite a page correctly at your normal pace | Words appear as you say them; nothing red. Amber is a near miss, not a mistake. |
| Recite in your melodic style, then fast drill style | Same — note which style produces amber or red words that were right |
| Try **Whisper Small** in Settings | Faster to start, less accurate — is it good enough on your phone? |
| Leave out a word | It shows red, struck through |
| Say a different word | Red with what you said beneath it |
| Pause ~3 s | "listening…" in the footer |
| Stay silent ~8 s | The next word fades in (grey, flagged) |
| Tap a blank line | The next word appears |
| Tap a bayt number | Reciting restarts from that bayt |
| Swipe to another page while reciting | Tracking continues from that page |
| Finish a page | The page turns by itself |
| Long-press a red word → **Not a mistake** | It turns normal and its flag goes |
| Tap the mic to stop | Summary card: bayts, mistakes, revealed |
| Back to **Read** | Flagged words carry a red-brown underline; long-press a half-line to flag/unflag |

Turn the mic off while the permission prompt or the download is showing: the mic
must not come on afterwards.

Early runs will flag words wrongly (recognizer noise, or the 8 s reveal firing while you
recite correctly). Clear them under **Library → Settings (gear) → Flags → Clear all flags**.

If voice can't start (microphone off, no internet for the first download), the footer says why and the
sitting carries on by tap: tap the blank holding the next word to reveal it.

## Step 3 — send me what you saw

- Which words went amber/red that you recited correctly (bayt and word), and in which
  style. These tune `MatchTuning` in `Core/Matching/RecitationTracker.swift`.
- How long the first download and "Preparing…" took, and whether recognition
  keeps up with you (the lag between saying a word and seeing it).
- The recognizer log. In **Console.app** on the Mac, select the iPhone, filter
  `subsystem:com.farhan.hifzalmutun category:speech`, recite a bayt or two, and copy
  the lines. Each shows `volatile` (Whisper's current guess) or `FINAL` (confirmed)
  and the text.

## Simulator: debug launch arguments (DEBUG builds only)

Set in Xcode (**Product → Scheme → Edit Scheme → Run → Arguments**) or with
`xcrun simctl launch … <args>`:

| Argument | Effect |
|---|---|
| `-openReaderMatn shatibiyya -openReaderPage 8` | Open straight into a page |
| `-debugRecite "يقول راجي\|رحمة\|~الغفور"` | Replay a recitation (`\|` separates results, `~` marks volatile) |
| `-debugReciteInterval 0.8` | Pace the replay like live speech (stays live after) |
| `-debugStopAfter 12` | Stop the sitting after 12 s (shows the summary) |
| `-debugVoiceFail mic\|download` | Simulate a failure to start |
