# False alarms on professional recitations of short suras (EveryAyah): every
# short vowel the model hears differently from the text is a false alarm.
# The Quran is the model's own training domain, so this is a best case.
# Usage: reciters.py MODEL.mlpackage AUDIO_DIR
import sys, os, subprocess, numpy as np, torch, librosa, coremltools as ct
from probe import phonemes, align, model
from quran_transcript import Aya, alphabet as alph
from quran_muaalem.decode import phonemes_level_greedy_decode

H = "َُِ"
RECITERS = ["Husary_64kbps", "Minshawy_Murattal_128kbps", "Alafasy_64kbps"]
SURAS = {1: 7, 97: 5, 103: 3, 108: 3, 109: 6, 110: 3, 111: 5, 112: 4, 113: 5, 114: 6}
mu = model()
vocab = mu.multi_level_tokenizer.id_to_vocab["phonemes"]
ml = ct.models.MLModel(sys.argv[1])
os.makedirs(sys.argv[2], exist_ok=True)

vowels = swapped = ayat = too_long = 0
for who in RECITERS:
    for sura, n in SURAS.items():
        for aya in range(1, n + 1):
            name = f"{sura:03d}{aya:03d}.mp3"
            path = os.path.join(sys.argv[2], who + "_" + name)
            if not os.path.exists(path):
                subprocess.run(["curl", "-sf", "-o", path, f"https://everyayah.com/data/{who}/{name}"], check=True)
            wave, _ = librosa.load(path, sr=16000, mono=True)
            wave, _ = librosa.effects.trim(wave, top_db=35)
            wave = np.concatenate([np.zeros(3200, np.float32), wave, np.zeros(3200, np.float32)])
            x = mu.processor([wave], sampling_rate=16000, return_tensors="np")["input_features"].astype(np.float32)
            if x.shape[1] > 500:                   # over the model's 10 s window
                too_long += 1
                continue
            hyp = phonemes_level_greedy_decode(torch.tensor(ml.predict({"input_features": x})["log_probs"]).exp(), vocab)[0].text
            ref = phonemes(Aya(sura, aya).get().uthmani).replace(alph.uthmani.space, "")
            last = len(ref) - 3                    # the pause changes the final vowel
            subs = [(i, a, b) for k, i, a, b in align(ref, hyp)[1] if k == "sub" and a in H and b in H and i < last]
            ayat += 1; vowels += sum(c in H for c in ref[:last]); swapped += len(subs)
            for i, a, b in subs: print(f"  {who} {sura}:{aya} {ref[max(0,i-5):i]}[{a}→{b}]{ref[i+1:i+4]}")
    print(f"-- after {who}: {ayat} ayat, {swapped} vowel swaps in {vowels} short vowels")
if vowels == 0:
    print(f"\nNo short vowels analysed: {too_long} ayat skipped as longer than the model's window")
else:
    print(f"\nFalse alarms: {swapped} of {vowels} short vowels ({swapped/vowels:.2%}) over {ayat} ayat; "
          f"{too_long} ayat skipped as longer than the model's window")
