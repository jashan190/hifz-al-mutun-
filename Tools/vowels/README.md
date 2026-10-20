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

## Plan in the app

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
