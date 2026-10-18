# Writes Resources/Phonemes/<id>.phonemes.json: for every half-line, the
# expected phonemes of each of its words (as the app splits them), so the app
# can check what the phoneme model heard against them. A word with nothing
# to say (punctuation) gets "", and every word of a half-line whose phonemes
# don't split back into its words gets null: it is left to Whisper alone.
# Usage: build_phonemes.py matn.json...
import json, sys, os
from probe import phonemes
from uthconv import uthmani
from quran_transcript import alphabet as alph

def words_of(path):
    m = json.load(open(path))
    if "pages" in m:
        for p in m["pages"]:
            for it in p["items"]:
                if it.get("type") == "bayt":
                    for h in ("sadr", "ajuz"): yield it["n"], h, [w["text"] for w in it[h]["words"]]
    else:
        for b in m["bayts"]:
            for h in ("sadr", "ajuz"): yield b["number"], h, [w["text"] for w in b[h + "Words"]]

for path in sys.argv[1:]:
    matn_id = json.load(open(path))["id"]
    halves, split, whole = {}, 0, 0
    for n, h, words in words_of(path):
        whole += 1
        spoken = [uthmani(w) for w in words]
        said = [u for u in spoken if u]
        out = [None] * len(words)
        try:
            parts = phonemes(" ".join(said)).split(alph.uthmani.space)
        except Exception:
            parts = []
        if len(parts) == len(said):
            it = iter(parts)
            out = [next(it) if u else "" for u in spoken]
            split += 1
        halves[f"{n}.{h}"] = out
    dest = os.path.join(os.path.dirname(path), "..", "Phonemes", f"{matn_id}.phonemes.json")
    json.dump({"version": 1, "halves": halves}, open(dest, "w"), ensure_ascii=False, separators=(",", ":"))
    print(f"{matn_id}: {split}/{whole} half-lines split into their words → {dest}")
