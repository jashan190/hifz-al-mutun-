import subprocess, librosa, sys
from probe import phonemes, transcribe, align
from uthconv import verse
from quran_transcript import alphabet as alph
H = set("َُِ")
cases = [
    # (expected text, what is said: one planted vowel slip each, or none)
    ("بَدَأْتُ بِبِسْمِ اللهِ فِي النَّظْمِ أَوَّلَا", None),
    ("بَدَأْتُ بِبِسْمِ اللهِ فِي النَّظْمِ أَوَّلَا", "بَدَأْتِ بِبِسْمِ اللهِ فِي النَّظْمِ أَوَّلَا"),
    ("بَدَأْتُ بِبِسْمِ اللهِ فِي النَّظْمِ أَوَّلَا", "بَدَأْتُ بِبِسْمِ اللهِ فِي النَّظْمَ أَوَّلَا"),
    ("وَثَلَّثْتُ أَنَّ الْحَمْدَ لِلهِ دَائِمًا", None),
    ("وَثَلَّثْتُ أَنَّ الْحَمْدَ لِلهِ دَائِمًا", "وَثَلَّثْتُ أَنَّ الْحَمْدُ لِلهِ دَائِمًا"),
    ("وَبَعْدُ فَحَبْلُ اللهِ فِينَا كِتَابُهُ", None),
    ("وَبَعْدُ فَحَبْلُ اللهِ فِينَا كِتَابُهُ", "وَبَعْدُ فَحَبْلِ اللهِ فِينَا كِتَابُهُ"),
    ("وَبَعْدُ فَحَبْلُ اللهِ فِينَا كِتَابُهُ", "وَبَعْدُ فَحَبْلُ اللهِ فِينَا كَتَابُهُ"),
]
for k, (expected, said) in enumerate(cases):
    spoken = said or expected
    aiff = f"tts{k}.aiff"
    subprocess.run(["say", "-v", "Majed", "-r", "120", "-o", aiff, spoken], check=True)
    wave, _ = librosa.load(aiff, sr=16000, mono=True)
    ref = phonemes(verse(expected)).replace(alph.uthmani.space, "")
    hyp = "".join(transcribe(wave)[0])
    _, ops = align(ref, hyp)
    swaps = [ref[max(0,i-5):i] + "[" + a + "→" + b + "]" + ref[i+1:i+4] for kind, i, a, b in ops if kind == "sub" and a in H and b in H]
    print(("PLANTED " if said else "correct ") + spoken)
    print("   vowel swaps found:", swaps or "none")
    print("   HYP", hyp)
