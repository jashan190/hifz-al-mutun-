import json, sys, time, re
import numpy as np, torch, librosa
from quran_transcript import MoshafAttributes
from quran_transcript.phonetics.operations import OPERATION_ORDER
from quran_transcript.phonetics.conv_base_operation import sub_with_mapping
from quran_transcript import alphabet as alph
from uthconv import verse

moshaf = MoshafAttributes(rewaya="hafs", madd_monfasel_len=2, madd_mottasel_len=4, madd_mottasel_waqf=4, madd_aared_len=2)

def phonemes(uth):
    text, maps = sub_with_mapping(r"\s+", alph.uthmani.space, uth)
    for op in OPERATION_ORDER:
        text, maps = op.apply(text, moshaf, maps, sura_idx=0)
    return text

def ref_for(matn_path, first, last):
    m = json.load(open(matn_path))
    out = []
    for p in m["pages"]:
        for it in p["items"]:
            if it.get("type") != "bayt" or not (first <= it["n"] <= last): continue
            for h in ("sadr", "ajuz"):
                u = verse(it[h]["text"])
                out.append((it["n"], h, u, phonemes(u)))
    return out

_model = None
def model():
    global _model
    if _model is None:
        from quran_muaalem import Muaalem
        _model = Muaalem(device="cpu", dtype=torch.float32)
    return _model

def transcribe(wave, max_s=15):
    from quran_muaalem.decode import phonemes_level_greedy_decode
    mu = model()
    # chunk at silences, ≤ 15 s each
    iv = librosa.effects.split(wave, top_db=35, frame_length=1024, hop_length=256)
    chunks, cur = [], None
    for a, b in iv:
        if cur is None: cur = [a, b]
        elif b - cur[0] <= max_s * 16000 or b - a < 1.0 * 16000: cur[1] = b
        else: chunks.append(cur); cur = [a, b]
    if cur: chunks.append(cur)
    texts = []
    for a, b in chunks:
        a = max(0, a - 3200); b = min(len(wave), b + 3200)
        f = mu.processor([wave[a:b]], sampling_rate=16000, return_tensors="pt")
        with torch.no_grad():
            outs = mu.model(**f, return_dict=False)[0]
        probs = torch.nn.functional.softmax(outs["phonemes"], dim=-1).float()
        u = phonemes_level_greedy_decode(probs, mu.multi_level_tokenizer.id_to_vocab["phonemes"])[0]
        texts.append(u.text)
    return texts, chunks

def align(ref, hyp):
    s, t = ref, hyp
    d = np.zeros((len(s)+1, len(t)+1), dtype=np.int32)
    d[:, 0] = range(len(s)+1); d[0, :] = range(len(t)+1)
    for i in range(1, len(s)+1):
        for j in range(1, len(t)+1):
            d[i, j] = min(d[i-1, j]+1, d[i, j-1]+1, d[i-1, j-1] + (s[i-1] != t[j-1]))
    ops = []; i, j = len(s), len(t)
    while i or j:
        if i and j and d[i, j] == d[i-1, j-1] + (s[i-1] != t[j-1]):
            if s[i-1] != t[j-1]: ops.append(("sub", i-1, s[i-1], t[j-1]))
            i -= 1; j -= 1
        elif i and d[i, j] == d[i-1, j] + 1:
            ops.append(("del", i-1, s[i-1], "")); i -= 1
        else:
            ops.append(("ins", i, "", t[j-1])); j -= 1
    return d[len(s), len(t)], ops[::-1]

if __name__ == "__main__":
    audio, matn, first, last = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    refs = ref_for(matn, first, last)
    ref = "".join(r[3].replace(alph.uthmani.space, "") for r in refs)
    wave, _ = librosa.load(audio, sr=16000, mono=True)
    t0 = time.time()
    texts, chunks = transcribe(wave)
    print(f"model time {time.time()-t0:.1f}s for {len(wave)/16000:.1f}s audio, {len(chunks)} chunks")
    hyp = "".join(texts)
    dist, ops = align(ref, hyp)
    print(f"REF {len(ref)} phonemes, edits {dist}, PER {dist/len(ref):.2%}")
    VOWELS = set("َُِّْ") | set("اۥۦ")
    for kind, i, a, b in ops:
        ctx = ref[max(0, i-6):i] + "[" + ref[i:i+1] + "]" + ref[i+1:i+6]
        tag = "VOWEL" if (a in VOWELS or b in VOWELS) else "CONS "
        print(f"  {tag} {kind} ref={a!r} heard={b!r}  {ctx}")
    json.dump({"ref": ref, "hyp": hyp, "texts": texts}, open(audio + ".out.json", "w"), ensure_ascii=False)
