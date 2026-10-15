"""Shared Arabic normalization for the content pipeline.

The app will apply the *same* rules at runtime (in Core/Matching) so that
voice-test matching lines up with what we store here. Keep the two in sync.

Rules (from the project spec):
  - strip all harakat (tashkeel) and other combining marks
  - strip tatweel (the ـ stretching character)
  - أ إ آ ٱ  ->  ا
  - ى  ->  ي
  - ة  ->  ه

We also drop anything that is not an Arabic letter from the normalized form
(punctuation, parentheses, digits, spaces inside a token), because the
normalized form is only ever used for *matching*, never for display.
"""

import re
import sys
import unicodedata

# Combining marks we want gone: Arabic tashkeel, Quranic annotation signs,
# superscript alef, etc. This covers U+0610–061A, U+064B–065F, U+0670,
# U+06D6–06DC, U+06DF–06E8, U+06EA–06ED.
_TASHKEEL = re.compile(
    "[ؐ-ًؚ-ٰٟۖ-ۜ۟-۪ۨ-ۭ]"
)

_TATWEEL = "ـ"

# Letter folding.
_LETTER_MAP = {
    "أ": "ا",  # أ -> ا
    "إ": "ا",  # إ -> ا
    "آ": "ا",  # آ -> ا
    "ٱ": "ا",  # ٱ (alef wasla) -> ا
    "ى": "ي",  # ى -> ي
    "ة": "ه",  # ة -> ه
}

# Keep only these after folding: Arabic letters (incl. hamza seats ؤ ئ ء).
_ARABIC_LETTERS = re.compile("[^ء-غف-ي]")


def normalize(text: str) -> str:
    """Return the match-only normalized form of an Arabic token or phrase."""
    # Canonical decomposition first, so stray composed forms split predictably.
    text = unicodedata.normalize("NFKD", text)
    text = _TASHKEEL.sub("", text)
    text = text.replace(_TATWEEL, "")
    for src, dst in _LETTER_MAP.items():
        text = text.replace(src, dst)
    # NFKD may have re-introduced marks for some letters; strip again.
    text = _TASHKEEL.sub("", text)
    text = _ARABIC_LETTERS.sub("", text)
    return text


if __name__ == "__main__":
    # Tiny self-check so you can eyeball the rules.
    samples = [
        ("يَقُولُ", "يقول"),
        ("الْأَطْفَالِ", "الاطفال"),
        ("آمَنُوا", "امنوا"),
        ("رَحْمَةِ", "رحمه"),
        ("عَلَى", "علي"),
        ("(تُحْفَةِ", "تحفه"),
    ]
    ok = True
    for raw, expected in samples:
        got = normalize(raw)
        flag = "ok" if got == expected else "FAIL"
        if got != expected:
            ok = False
        print(f"  {flag}: {raw!r} -> {got!r} (expected {expected!r})")
    print("all good" if ok else "SOME CHECKS FAILED")
    sys.exit(0 if ok else 1)
