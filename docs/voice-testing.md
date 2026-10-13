# Testing voice on your iPhone

Voice review runs Apple's on-device speech recognizer, which isn't available in the
Simulator. Everything else (the reveal, mistakes, flags, page turns, the summary)
can be exercised in the Simulator with the debug launch arguments at the end.

## One-time setup

1. iPhone on **iOS 26 or later**, connected by cable (or on the same Wi-Fi after
   the first cable run).
2. On the phone: **Settings → Privacy & Security → Developer Mode → On** (it restarts).
3. Signing: `Config/Local.xcconfig` (git-ignored) holds this Mac's team and bundle
   id. On another Mac, copy `Config/Local.xcconfig.example` and fill it in.
4. `xcodegen generate && open HifzAlMutun.xcodeproj`, pick the iPhone in the device
   menu, press **⌘R**. The first run creates a development certificate; on the phone,
   trust it under **Settings → General → VPN & Device Management**.

## Step 1 — the gate: does Arabic work on this phone?

With the phone selected, press **⌘U** (run tests). `transcribesArabicClip` runs only
on a device. It:
- resolves an Arabic locale (prints e.g. `SPIKE Arabic locale: ar-SA`) — failing here
  means this phone's speech model doesn't support Arabic;
- transcribes the bundled Shatibiyyah clip and prints the transcript.

If it fails, stop and tell me: the next options are Apple's older
`DictationTranscriber`, then WhisperKit (roadmap Phase F).

## Step 2 — recite

Open a matn, switch to **Memorize**, tap the mic. The first time, iOS asks for the
microphone and speech recognition, and may download the Arabic model (the footer
shows "Downloading Arabic voice N%").

Try each of these and note what happens:

| Try | Expect |
|---|---|
| Recite a page correctly at your normal pace | Words appear as you say them; nothing red. Amber is a near miss, not a mistake. |
| Recite in your melodic style, then fast drill style | Same — note which style produces amber or red words that were right |
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

If voice can't start (permission off, no Arabic model), the footer says why and the
sitting carries on by tap: tap the blank holding the next word to reveal it.

## Step 3 — send me what you saw

- Which words went amber/red that you recited correctly (bayt and word), and in which
  style. These tune `MatchTuning` in `Core/Matching/RecitationTracker.swift`.
- The recognizer log. In **Console.app** on the Mac, select the iPhone, filter
  `subsystem:com.farhan.hifzalmutun category:speech`, recite a bayt or two, and copy
  the lines. Each shows `volatile`/`FINAL`, the audio range, and the text — this
  checks the tracker's assumption that a volatile result is replaced by the next one
  for the same audio range.

## Simulator: debug launch arguments (DEBUG builds only)

Set in Xcode (**Product → Scheme → Edit Scheme → Run → Arguments**) or with
`xcrun simctl launch … <args>`:

| Argument | Effect |
|---|---|
| `-openReaderMatn shatibiyya -openReaderPage 8` | Open straight into a page |
| `-debugRecite "يقول راجي\|رحمة\|~الغفور"` | Replay a recitation (`\|` separates results, `~` marks volatile) |
| `-debugReciteInterval 0.8` | Pace the replay like live speech (stays live after) |
| `-debugStopAfter 12` | Stop the sitting after 12 s (shows the summary) |
| `-debugVoiceFail mic\|speech\|arabic` | Simulate a failure to start |
