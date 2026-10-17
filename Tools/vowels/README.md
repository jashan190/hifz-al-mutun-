# Vowel checking (spike)

Whisper can't judge harakat. With no prompt it writes no vowels. Prompted with
vowelled text, it writes them, but wrongly on a correct recitation, and it drops
whole bayts. These scripts test a phoneme model in its place:
[Quran Muaalem](https://github.com/obadx/quran-muaalem) (`obadx/muaalem-model-v3_2`).
It is a w2v-BERT 2.0 model (0.6B parameters, MIT) with CTC heads. It writes what
was said as phonemes, short vowels included, in the Quran Phonetic Script.

## Results (2026-10-16, `shatibiyya_clip`, bayts 1–10)

| Check | Result |
| --- | --- |
| Short vowels swapped (fatha/kasra/damma) on the correct recitation, one window per half-line | 1 of 275 (وُبَّلَا heard وَبَّلَا) |
| Phoneme error rate, all kinds | 9.5% — mostly style, not mistakes: ghunna and madd length, idgham across words |
| Planted vowel slips (macOS "Majed" voice) | 4 of 4 caught; one false alarm where the voice itself misread |
| Core ML, fp16 | 1.1 GB, same output as PyTorch on 19/20 half-lines, ~31 ms per half-line on the Mac |
| Core ML, int8 weights | 580 MB, same as fp16 |
| Core ML, 4-bit palettized | 292 MB, 14/20 identical, PER 10.1%, still 1 vowel swap |

Not yet measured: speed on an iPhone, and slips in a real person's voice.

## Test suites (2026-10-16, int8 Core ML model)

| Suite | Result |
| --- | --- |
| `suite.py`: 60 random half-lines (20 per matn), each read correctly and with one planted short-vowel slip by a speech-synthesis voice that reads the vowels as written | **49 of 57 slips caught (86%)**: endings and tanween 21/22, vowels inside a word 28/35. **No false alarm on the 57 correct readings.** 3 lines skipped because the voice itself misread them |
| `reciters.py`: 128 ayat of short suras by Husary, Minshawi and Alafasy | 0 vowel swaps in 1,099 short vowels. A sanity check only: these reciters are likely in the model's training data |
| `phonetize_all.py`: every half-line of the three matns | All 2,686 phonetize without an error (that is no crash, not a checked reference) |
| `build_phonemes.py`: phonemes split back into the app's words | Tuhfa 122/122, Jazariyya 216/218, Shatibiyya 2,288/2,346 half-lines; the rest are left to Whisper |

- Most misses are a word's first letter (وُ for وَ, عُنْ for عَنْ). The voice
  may not have said them; only a person's recording can tell.
- The Mac's own Arabic voice ("Majed") misreads too many lines to test with,
  so the suite uses [tts_arabic](https://github.com/nipponjo/tts_arabic)
  (FastPitch). It is installed from git into its own venv, and `suite.py`
  runs `say.py` with it through `TTS_PY`:

  ```sh
  uv venv --python 3.12 tts/.venv
  uv pip install --python tts/.venv/bin/python "git+https://github.com/nipponjo/tts_arabic" soundfile
  TTS_PY=tts/.venv/bin/python .venv/bin/python Tools/vowels/suite.py Muaalem_int8.mlpackage 20 Resources/Content/{tuhfa,jazariyya,shatibiyya}.json
  ```

- A known false-alarm source the suites can't see: the speech voice reads the
  same spelling the reference is built from. A half-line that starts on a
  hamzat wasl other than the article is phonetized as written; only one does
  (ابْنٍ, al-Jazariyyah).

## How the pieces fit

- `uthconv.py` rewrites a line of the matn in the Quran's spelling, which the
  phonetizer (`quran-transcript`) expects:
  - ٱ for the article
  - ٱللَّه
  - ى at the end of فِى
  - ًا for اً
  - shadda *before* its vowel; without this, gemination and assimilation are lost
  - the connecting noon dropped, since the tanween produces it
- `probe.py`:
  - phonetizes the expected text (the operations only; the library's sifat step
    crashes on some words, e.g. ٱلنَّاسِ)
  - transcribes audio at silences, aligns the two, and lists the differences
- `sens.py`: planted vowel slips spoken by the Mac's Arabic voice.
- `convert.py`: exports the phoneme head to Core ML.
  - Variable input length; no attention mask, since its −inf overflows fp16
    into NaN.
  - Adds a converter for `new_ones`.
- `quant.py`: int8 or palettized weights.
- `parity.py`: Core ML against PyTorch, per half-line, with timing.

Setup (Python 3.12):

```sh
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python quran-muaalem librosa "numba>=0.61.2" "transformers<4.56" coremltools
ffmpeg -i Tests/SpeechTests/Fixtures/shatibiyya_clip.m4a -ar 16000 -ac 1 clip.wav
.venv/bin/python Tools/vowels/probe.py clip.wav Resources/Content/shatibiyya.json 1 10
```

## In the app (branch `vowel-checking-app`)

- `build_phonemes.py` writes `Resources/Content/<id>.phonemes.json`: each
  word's expected phonemes, as the app splits the words.
- `Core/Vowels`:
  - `PhonemeFeatures`: the feature extractor ported to Swift.
  - `PhonemeModel`: Core ML and greedy CTC decoding.
  - `VowelJudge`: aligns the expected phonemes inside what was heard, with
    the ends of the heard text free, and reports only fatha/damma/kasra swaps.
  - `VowelChecker`: puts these together for words the tracker has placed.
- Each final Whisper result carries its audio. The session checks the words
  it settled when each was heard right (or skipped). A slip turns the word
  into a mistake, shown as said (الْحَمْدَ for الْحَمْدُ), with the changed
  letter marked.
- The model is not bundled. DEBUG builds load it from `-vowelModel <path>`.
- `fixtures.py` writes the Swift parity fixtures; `VowelTests` compares
  against them. With `TEST_RUNNER_VOWEL_MODEL=<path>` it also runs the model
  end to end.
- The export takes up to 30 s (`convert.py OUT 1500`), in fixed lengths of
  1 s each. The app pads a clip's features with zeros (the clip's mean) up
  to the next length and drops the padded frames' output. On the 20
  windows, no padding choice changed a vowel heard.

### Where it was verified

| Check | Where | Result |
| --- | --- | --- |
| Swift features vs Python | Simulator (`VowelTests`) | largest difference 1.3e-5 |
| Swift features → Core ML → decoding vs Python, 20 half-line windows | Mac's Core ML (`Tools/vowels/swift`) | variable length: 20/20 identical; fixed lengths: 0 vowels heard differently (16/20 identical; the rest differ in ghunna length and the like); median 24–30 ms per half-line |
| Running the model | iOS Simulator | **crashes** (a segfault in Core ML's CPU shape kernel), with either export, so the app never loads it there |
| Live path: the correct clip streamed through Whisper and the session; each check's words and audio recorded in the Simulator and judged on the Mac | Simulator + Mac (`vowelCheckIsQuietOnTheCorrectClip`, then `Tools/vowels/swift`) | 6 checks over 62 of 102 words, **0 slips**: each final's audio lines up with the words it settles. The other 40 words were in passages that also held a word Whisper judged wrong, or in the last guess, which carries no audio |
| Running the model | iPhone | not yet |

## Plan

1. **Build time.** `Tools/` phonetizes every hemistich and stores its phonemes,
   plus a mapping back to letters, in the content JSON. Lines it can't phonetize
   (e.g. كَالُاتْرُجِّ) are checked by Whisper alone.
2. **Run time.**
   - Whisper keeps tracking the place.
   - For each confirmed segment, the phoneme model runs on that audio.
   - Only a fatha/kasra/damma *substitution* on a word Whisper already matched
     is flagged, with a confidence floor.
   - Not flagged: the vowel at a pause, ghunna and madd length, assimilation.
3. **Settings.** "Vowel checking" is an opt-in download (int8, 580 MB) next to
   the voice model.
4. **Port to Swift.** The feature extractor (`SeamlessM4TFeatureExtractor`):
   80 mel bins, per-utterance normalization, and stride-2 stacking to 160. It
   needs its own parity check.
