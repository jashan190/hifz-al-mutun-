# Writes the Swift parity fixtures into Tests/SpeechTests/Fixtures:
#   shatibiyya_clip_16k.flac   the clip at 16 kHz (lossless, so Swift reads
#                              the very samples Python used)
#   vowel_windows.json         the clip's windows (one per half-line, cut at
#                              silences as parity.py does) and the phonemes the
#                              Core ML model hears in each, with Python features
#   vowel_window0.f32          Python's features for window 0 (float32, LE)
# Usage: fixtures.py MODEL.mlpackage clip.wav
import sys, json, subprocess, os, numpy as np, torch, librosa, coremltools as ct
from probe import model
from quran_muaalem.decode import phonemes_level_greedy_decode

out = os.path.join(os.path.dirname(__file__), "../../Tests/SpeechTests/Fixtures")
mu = model()
vocab = mu.multi_level_tokenizer.id_to_vocab["phonemes"]
ml = ct.models.MLModel(sys.argv[1])
wave, _ = librosa.load(sys.argv[2], sr=16000, mono=True)
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", sys.argv[2], "-ar", "16000", "-ac", "1",
                "-sample_fmt", "s16", os.path.join(out, "shatibiyya_clip_16k.flac")], check=True)

iv = librosa.effects.split(wave, top_db=35, frame_length=1024, hop_length=256)
wins, cur = [], None
for a, b in iv:
    if cur is None: cur = [a, b]
    elif b - cur[0] <= 6 * 16000 or b - a < 16000: cur[1] = b
    else: wins.append(cur); cur = [a, b]
wins.append(cur)

windows = []
for k, (a, b) in enumerate(wins):
    a = max(0, a - 3200); b = min(len(wave), b + 3200)
    x = mu.processor([wave[a:b]], sampling_rate=16000, return_tensors="np")["input_features"].astype(np.float32)
    if k == 0: x[0].astype("<f4").tofile(os.path.join(out, "vowel_window0.f32"))
    logp = ml.predict({"input_features": x})["log_probs"]
    text = phonemes_level_greedy_decode(torch.tensor(logp).exp(), vocab)[0].text
    windows.append({"from": int(a), "to": int(b), "phonemes": text})
json.dump({"windows": windows}, open(os.path.join(out, "vowel_windows.json"), "w"), ensure_ascii=False, indent=1)
print(f"{len(windows)} windows; window 0 features {x.shape if len(windows) == 1 else ''}")
