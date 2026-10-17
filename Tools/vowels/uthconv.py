import re
TASHKEEL = "ًٌٍَُِّْ"
def uthmani(word):
    w = word.replace("ـ", "")
    w = re.sub("ۨ[َ-ْ]?", "", w)                  # connecting noon (tanween does it)
    w = re.sub("[^ء-ْٰٱ]", "", w)
    if not w: return ""
    w = re.sub("^الله", "ٱللَّه", w)            # اللهِ
    w = re.sub("^لِله", "لِلَّه", w)            # لِلهِ
    w = re.sub("^((?:[وفبك][َِ])?)ا(?=ل)", lambda m: m.group(1) + "ٱ", w)  # the article
    w = w.replace("اً", "ًا")                     # اً → ًا
    w = re.sub("ِي$", "ِى", w)                     # فِي → فِى
    w = re.sub("([\u064B-\u0650])\u0651", "\u0651\\1", w)           # shadda before its vowel
    return w
def verse(text):
    return " ".join(x for x in (uthmani(t) for t in text.split()) if x)
