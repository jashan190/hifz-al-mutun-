# Hifz al-Mutun

[![CI](https://github.com/jashan190/hifz-al-mutun-/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/jashan190/hifz-al-mutun-/actions/workflows/ci.yml)

A native iOS app (SwiftUI, iOS 26+) for memorizing three classical
Arabic didactic poems (mutun) in tajwīd and qirā’āt: **Tuhfat al-Atfal**,
**al-Muqaddimah al-Jazariyyah**, and **ash-Shatibiyyah (Hirz al-Amani)**.

## Getting started

```sh
# one-time tool installs
brew install xcodegen
brew install poppler          # only needed for the content pipeline in Tools/

# generate and open the Xcode project (the .xcodeproj is disposable)
cd "hifz-al-mutun-"
xcodegen generate
open HifzAlMutun.xcodeproj
```

Pick an iPhone (iOS 26+) and press Run. The app opens to the Library; tap a
matn to open the paged Reader. Voice review listens with Whisper (WhisperKit),
which downloads its model on first use and also runs in the Simulator with the
Mac's microphone. Tests: `HifzAlMutunTests` (⌘U).
GitHub Actions runs the tests, an unsigned device build and the content
validator on every PR — see [docs/ci.md](docs/ci.md).

## Project layout

```
App/           app entry + Library (root screen)
Core/
  Models/      read-only content models (Matn, MatnPage, Bayt, Hemistich, Word)
  Content/     loads the bundled matn JSON
  Design/      theme tokens, page font, hemistich renderer, shared controls
  Matching/    Arabic normalizer, recitation index + tracker, word reveal
  Speech/      SpeechSource protocol; WhisperKit live-mic source and models
  Settings/    appearance mode
Features/
  Reader/      page screen, page view, mode toggle, mic, voice session
  Settings/    settings sheet
Tests/         unit tests (matching, Whisper fragments) + opt-in Whisper run
Resources/
  Content/     bundled matn JSON  (tuhfa.json, jazariyya.json, shatibiyya.json)
  Fonts/
Tools/         Python content pipeline (runs on your Mac, not in the app)
  sources/     hand-verified text transcriptions
source/        the original PDFs
docs/          schema + verification notes
project.yml    XcodeGen manifest — the source of truth for the Xcode project
```

## Content vs progress

Text and layout are **read-only JSON** bundled in the app (one file per matn).
A user's progress, marks, and slip history will live in **SwiftData** (not yet
built) and
reference bayts by `(matnID, baytNumber)`. The two are deliberately separate so
that re-building a matn's text never erases a user's marks.

## Phases

- **Phase 0 (done):** project setup, content JSON schema, pipeline scripts, and
  `tuhfa.json` (Tuhfat al-Atfal, 61 bayts) and `jazariyya.json`
  (al-Muqaddimah al-Jazariyyah, 109 bayts) built, validated, and loading in the app.
  ash-Shatibiyyah (1,173 bayts, Suwaid edition) added — see `SHATIBIYYAH_DATA.md`.
- **Phase 1 (done):** the Reader and page view, matching the PDF visually.
- **Phase 2:** Memorize, test modes, marks/slips, rotation, Today, Progress,
  Mistake history.
- **Phase 3:** reference audio — forced alignment + listen-and-loop.
- **Phase 4:** voice review. Word-by-word follow-along is done: reciting in
  Memorize mode reveals the matn via Whisper (WhisperKit, on-device), matched
  against the known text. Still to come: device gate, hardening, mistake
  detection, flags, and the Review screen — see `docs/voice-roadmap.md`.
  Apple's `SpeechAnalyzer` was dropped: it didn't recognise Arabic on device.
- **Phase 5:** polish — finished-matn taper, settings, backup/export, widgets,
  reminders.

See `docs/content-schema.md` for the JSON shape and `Tools/README.md` for the
pipeline.
