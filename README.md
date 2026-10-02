# Hifz al-Mutun

A native iOS app (SwiftUI, SwiftData, iOS 18+) for memorizing three classical
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

Pick an iPhone simulator and press Run. The app currently opens to a Phase 0
screen that lists the bundled matn with its bayt/bab/page counts.

## Project layout

```
App/           app entry + root screen
Core/
  Models/      read-only content models (Matn, Bab, Bayt, Word)
  Content/     loads the bundled matn JSON
  Rotation/ Marks/ Audio/ Speech/ Matching/   (filled in later phases)
Features/      Today, Reader, Memorize, Test, Progress,
               MistakeHistory, VoiceTest, Settings  (later phases)
Resources/
  Content/     bundled matn JSON  (tuhfa.json, jazariyya.json)
  Fonts/ Audio/
Tools/         Python content pipeline (runs on your Mac, not in the app)
  sources/     hand-verified text transcriptions
source/        the original PDFs
docs/          schema + verification notes
project.yml    XcodeGen manifest — the source of truth for the Xcode project
```

## Content vs progress

Text and layout are **read-only JSON** bundled in the app (one file per matn).
A user's progress, marks, and slip history will live in **SwiftData** and
reference bayts by `(matnID, baytNumber)`. The two are deliberately separate so
that re-building a matn's text never erases a user's marks.

## Phases

- **Phase 0 (done):** project setup, content JSON schema, pipeline scripts, and
  `tuhfa.json` (Tuhfat al-Atfal, 61 bayts) and `jazariyya.json`
  (al-Muqaddimah al-Jazariyyah, 109 bayts) built, validated, and loading in the app.
  ash-Shatibiyyah (the large scanned matn) is still to be done.
- **Phase 1:** the Reader and page view, matching the PDF visually.
- **Phase 2:** Memorize, test modes, marks/slips, rotation, Today, Progress,
  Mistake history.
- **Phase 3:** reference audio — forced alignment + listen-and-loop.
- **Phase 4:** voice test with WhisperKit (on-device, Arabic).
- **Phase 5:** polish — finished-matn taper, settings, backup/export, widgets,
  reminders.

See `docs/content-schema.md` for the JSON shape and `Tools/README.md` for the
pipeline.
