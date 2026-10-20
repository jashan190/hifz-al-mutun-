# Planted-slip suite: for random half-lines of each matn, the Mac's Arabic
# voice reads the line correctly and with one short vowel changed. The
# shipping Core ML model must flag the changed vowel and nothing on the
# correct reading. Usage: suite.py MODEL.mlpackage N_PER_MATN matn.json...
import sys, random, re, subprocess, tempfile, os, numpy as np, torch, librosa, coremltools as ct
from probe import phonemes, align, model
from uthconv import verse
from lines import half_lines
from quran_muaalem.decode import phonemes_level_greedy_decode
from quran_transcript import alphabet as alph

H = "َُِ"
mu = model()
vocab = mu.multi_level_tokenizer.id_to_vocab["phonemes"]
ml = ct.models.MLModel(sys.argv[1])
per = int(sys.argv[2])
rng = random.Random(7)
tmp = tempfile.mkdtemp()

def ref(text): return phonemes(verse(text)).replace(alph.uthmani.space, "")

# VOICE=majed uses the Mac's voice (it misreads some lines); otherwise
# TTS_PY names a Python with tts_arabic (FastPitch, reads the vowels as written).
def speak(text):
    out = os.path.join(tmp, "x.wav")
    if os.environ.get("VOICE") == "majed":
        subprocess.run(["say", "-v", "Majed", "-r", "120", "-o", out.replace(".wav", ".aiff"), text], check=True)
        out = out.replace(".wav", ".aiff")
    else:
        subprocess.run([os.environ["TTS_PY"], "-W", "ignore", os.path.join(os.path.dirname(__file__), "say.py"), out, text],
                       check=True, capture_output=True)
    return out

def hear(text):
    wave, _ = librosa.load(speak(text), sr=16000, mono=True)
    wave = np.concatenate([np.zeros(3200, np.float32), wave, np.zeros(3200, np.float32)])
    x = mu.processor([wave], sampling_rate=16000, return_tensors="np")["input_features"].astype(np.float32)
    assert x.shape[1] <= 500, "longer than the model's 10 s window"
    out = ml.predict({"input_features": x})["log_probs"]
    return phonemes_level_greedy_decode(torch.tensor(out).exp(), vocab)[0].text

def swaps(r, hyp):
    return {i: b for k, i, a, b in align(r, hyp)[1] if k == "sub" and a in H and b in H}

def skeleton(p):
    """Letters and short vowels only: madd, ghunna length and qalqala vary
    with the voice, not with the reading."""
    p = re.sub("[اۥۦڇ]", "", p)
    return re.sub(r"(.)\1+", r"\1", p)

TANWEEN = "ًٌٍ"

def plant(text):
    """The line with one short vowel changed, and which kind: "inner" (inside
    a word, away from madd letters and shadda) or "ending" (a word's case
    ending or tanween). Never on the last word (waqf drops its vowel) or a
    hamza seat (أ إ ؤ ئ fix their own vowel). None when nothing fits."""
    words = text.split()
    spots = []
    for w in range(len(words) - 1):
        word = words[w]
        for m in re.finditer(r"([ء-ي])([َُِ])(?!ّ)(?=[ء-ي])", word):
            if word[m.end()] in "اوىي" or m.group(1) in "أإؤئ": continue
            spots.append(("inner", w, m.start(2), H))
        if "ۨ" in word: continue
        m = re.search(r"([ء-ي])([َُِ])$", word)
        if m and m.group(1) not in "أإؤئ": spots.append(("ending", w, m.start(2), H))
        m = re.search(r"([ء-ي])([ٌٍ])$", word)
        if m: spots.append(("ending", w, m.start(2), "ٌٍ"))
    if not spots: return None, None
    kind, w, at, choices = rng.choice(spots)
    new = rng.choice([v for v in choices if v != words[w][at]])
    words[w] = words[w][:at] + new + words[w][at + 1:]
    return " ".join(words), kind

totals = dict(lines=0, false=0, planted=0, caught=0, extra=0, skipped=0, badvoice=0, inner=0, inner_caught=0, ending=0, ending_caught=0)
for path in sys.argv[3:]:
    lines = [t for _, _, t in half_lines(path)]
    for text in rng.sample(lines, per):
        text = re.sub(r"[^ء-ْٰۨ ]", "", text).strip()
        text = re.sub(" +", " ", text)
        slipped, kind = plant(text)
        r = ref(text)
        try: diff = swaps(r, ref(slipped)) if slipped else {}
        except Exception: diff = {}
        if len(diff) != 1: totals["skipped"] += 1; continue
        (at, vowel), = diff.items()
        heard = hear(text)
        # The voice's own reading must be close to the text, or the line
        # says nothing about the model.
        if align(skeleton(r), skeleton(heard))[0] / len(skeleton(r)) > 0.15:
            totals["badvoice"] += 1; print("  voice misread:", r, "/", heard); continue
        base = swaps(r, heard)
        got = swaps(r, hear(slipped))
        # Caught only if the planted vowel itself is heard as planted (a swap
        # of a neighbouring vowel isn't a catch, and counts as an extra flag).
        hit = got.get(at) == vowel
        extra = [i for i in got if i != at and i not in base]
        totals["lines"] += 1; totals["false"] += len(base) > 0
        totals["planted"] += 1; totals["caught"] += hit; totals[kind] += 1; totals[kind + "_caught"] += hit; totals["extra"] += len(extra) > 0
        print(f"{'✓' if hit else '✗'} {kind:6} {'FA ' if base else '   '}{slipped}   (was: {text.split()[[i for i,(a,b) in enumerate(zip(text.split(), slipped.split())) if a!=b][0]]})")
    print(f"-- after {path.split('/')[-1]}: {totals}")
t = totals
print(f"\nCaught {t['caught']}/{t['planted']} planted slips ({t['caught']/t['planted']:.0%}); "
      f"false alarm on {t['false']}/{t['lines']} correct readings ({t['false']/t['lines']:.0%}); "
      f"inner {t['inner_caught']}/{t['inner']}, endings {t['ending_caught']}/{t['ending']}; "
      f"extra flags on {t['extra']} slipped readings; {t['skipped']} lines skipped, {t['badvoice']} misread by the voice")
