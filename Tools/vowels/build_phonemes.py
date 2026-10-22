# Writes Resources/Phonemes/<id>.phonemes.json: for every half-line, the
# expected phonemes of each of its words (as the app splits them), so the app
# can check what the phoneme model heard against them. A word with nothing
# to say (punctuation) gets "", and every word of a half-line whose phonemes
# don't split back into its words gets null: it is left to Whisper alone.
# Usage: build_phonemes.py matn.json...
import json, sys, os
from uthconv import uthmani
from quran_transcript import MoshafAttributes, alphabet as alph
from quran_transcript.phonetics.operations import OPERATION_ORDER
from quran_transcript.phonetics.conv_base_operation import sub_with_mapping

# Phonetize the expected Uthmani text to the Quran Phonetic Script (the
# operations only; the library's sifat step crashes on some words). Inlined from
# probe.py so building the reference needs only quran-transcript — not the audio
# stack (torch/librosa) that probe.py imports for transcription.
_moshaf = MoshafAttributes(rewaya="hafs", madd_monfasel_len=2, madd_mottasel_len=4,
                           madd_mottasel_waqf=4, madd_aared_len=2)


def phonemes(uth):
    text, maps = sub_with_mapping(r"\s+", alph.uthmani.space, uth)
    for op in OPERATION_ORDER:
        text, maps = op.apply(text, _moshaf, maps, sura_idx=0)
    return text

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
