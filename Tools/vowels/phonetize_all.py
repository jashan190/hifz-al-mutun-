# How many half-lines of each matn the phonetizer can handle.
import sys, collections
from probe import phonemes
from uthconv import verse
from lines import half_lines
for path in sys.argv[1:]:
    ok, bad, fails = 0, collections.Counter(), []
    for n, h, text in half_lines(path):
        try: phonemes(verse(text)); ok += 1
        except Exception as e: bad[type(e).__name__] += 1; fails.append((n, h, text))
    total = ok + sum(bad.values())
    print(f"{path.split('/')[-1]}: {ok}/{total} half-lines phonetize ({ok/total:.1%}); failures {dict(bad)}")
    for f in fails[:6]: print("   ", *f)
