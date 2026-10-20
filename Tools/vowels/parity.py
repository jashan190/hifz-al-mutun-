import sys, time, numpy as np, torch, librosa, coremltools as ct
from probe import model, align, ref_for
from quran_muaalem.decode import phonemes_level_greedy_decode
from quran_transcript import alphabet as alph
pkg = sys.argv[1]
SHAPES = [150, 250, 400]
mu = model()
vocab = mu.multi_level_tokenizer.id_to_vocab["phonemes"]
ml = ct.models.MLModel(pkg, compute_units=ct.ComputeUnit[sys.argv[2] if len(sys.argv) > 2 else "ALL"])
wave, _ = librosa.load("clip.wav", sr=16000, mono=True)
iv = librosa.effects.split(wave, top_db=35, frame_length=1024, hop_length=256)
wins, cur = [], None
for a, b in iv:
    if cur is None: cur = [a, b]
    elif b - cur[0] <= 6 * 16000 or b - a < 16000: cur[1] = b
    else: wins.append(cur); cur = [a, b]
wins.append(cur)
def decode(logp):
    return phonemes_level_greedy_decode(torch.tensor(logp).exp(), vocab)[0].text
same, hyp_ml, hyp_pt, times = 0, [], [], []
for a, b in wins:
    a = max(0, a - 3200); b = min(len(wave), b + 3200)
    f = mu.processor([wave[a:b]], sampling_rate=16000, return_tensors="pt")
    x = f["input_features"].numpy().astype(np.float32); n = x.shape[1]
    with torch.no_grad():
        pt = decode(torch.log_softmax(mu.model(**f, return_dict=False)[0]["phonemes"], -1).numpy())
    t0 = time.time()
    out = ml.predict({"input_features": x})["log_probs"]
    times.append(time.time() - t0)
    mlh = decode(out)
    hyp_ml.append(mlh); hyp_pt.append(pt); same += mlh == pt
print(f"{pkg}: identical on {same}/{len(wins)} windows; median {np.median(times)*1000:.0f} ms per window (first {times[0]*1000:.0f} ms)")
refs = ref_for('Resources/Content/shatibiyya.json', 1, 10)
ref = "".join(r[3].replace(alph.uthmani.space, "") for r in refs)
H = set("َُِ")
for name, hyp in (("pytorch", hyp_pt), ("coreml", hyp_ml)):
    d, ops = align(ref, "".join(hyp))
    print(f"  {name}: PER {d/len(ref):.1%}, vowel swaps {sum(1 for k,i,x,y in ops if k=='sub' and x in H and y in H)}")
