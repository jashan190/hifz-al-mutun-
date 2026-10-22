#!/usr/bin/env python3
"""Build a matn JSON file from a hand-verified source .txt transcription.

Usage:
    python3 Tools/build_matn.py Tools/sources/tuhfa.txt Resources/Content/tuhfa.json

What it does:
  - parses the source format documented at the top of the .txt file
  - assigns each bayt a page/row using the matn's baytsPerPage (10 by default),
    counting bayts in order: page = (n-1)//perPage + 1, row = (n-1)%perPage + 1
  - splits each hemistich into words and attaches the normalized form of each
  - records bab ranges (first..last bayt under each heading)

The output is the read-only content the app bundles. Progress/marks live
separately in SwiftData and are never written here.
"""

import json
import sys
from normalize import normalize

SCHEMA_VERSION = 1


def parse_source(path):
    meta = {}
    babs = []            # list of {id, title, startBayt, endBayt}
    bayts = []           # list of {number, sadr, ajuz, babId}
    current_bab = None

    with open(path, encoding="utf-8") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue

            if stripped.startswith("%"):
                key, _, value = stripped[1:].partition("=")
                meta[key.strip()] = value.strip()
                continue

            if stripped.startswith("@"):
                body = stripped[1:].strip()
                bab_id, _, title = body.partition("|")
                bab_id = bab_id.strip()
                title = title.strip()
                current_bab = {
                    "id": bab_id,
                    "title": title,
                    "startBayt": None,
                    "endBayt": None,
                }
                babs.append(current_bab)
                continue

            # Otherwise: a bayt line "number <TAB> sadr <TAB> ajuz"
            parts = line.split("\t")
            parts = [p.strip() for p in parts if p.strip() != ""]
            if len(parts) != 3:
                raise ValueError(
                    f"{path}:{lineno}: expected 'number<TAB>sadr<TAB>ajuz', "
                    f"got {len(parts)} tab-separated field(s): {line!r}"
                )
            number_str, sadr, ajuz = parts
            try:
                number = int(number_str)
            except ValueError:
                raise ValueError(
                    f"{path}:{lineno}: bayt number is not an integer: {number_str!r}"
                )
            # A matn may have no sections at all; then bayts carry no babId.
            if current_bab is not None:
                if current_bab["startBayt"] is None:
                    current_bab["startBayt"] = number
                current_bab["endBayt"] = number
            bayts.append(
                {
                    "number": number,
                    "sadr": sadr,
                    "ajuz": ajuz,
                    "babId": current_bab["id"] if current_bab else None,
                }
            )

    return meta, babs, bayts


def parse_prose_source(path):
    """Parse a prose (hadith) source: metadata, then per hadith a '@ n | title'
    header, body lines, and a '= takhrij' line. Text inside «…» is matn."""
    meta = {}
    hadiths = []
    current = None   # {number, title, body_lines[], takhrij}

    with open(path, encoding="utf-8") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            if s.startswith("%"):
                key, _, value = s[1:].partition("=")
                meta[key.strip()] = value.strip()
                continue
            if s.startswith("@"):
                body = s[1:].strip()
                num_str, _, title = body.partition("|")
                current = {"number": int(num_str.strip()),
                           "title": title.strip(), "body_lines": [], "takhrij": ""}
                hadiths.append(current)
                continue
            if s.startswith("="):
                if current is None:
                    raise ValueError(f"{path}:{lineno}: '=' takhrij before any '@' hadith")
                current["takhrij"] = s[1:].strip()
                continue
            if current is None:
                raise ValueError(f"{path}:{lineno}: body before any '@' hadith")
            current["body_lines"].append(s)

    return meta, hadiths


def prose_words(text):
    """Split body text into role-tagged words. Text inside «…» is 'matn',
    everything else 'isnad'. Guillemets are stripped from stored text."""
    out = []
    buf = []
    role = "isnad"

    def flush():
        nonlocal buf
        if buf:
            w = "".join(buf)
            if w:
                out.append({"text": w, "norm": normalize(w), "role": role})
            buf = []

    for ch in text:
        if ch == "«":
            flush(); role = "matn"; continue
        if ch == "»":
            flush(); role = "isnad"; continue
        if ch.isspace():
            flush(); continue
        buf.append(ch)
    flush()
    return out


def build_prose(meta, hadiths):
    out_hadiths = []
    for h in hadiths:
        body_text = " ".join(h["body_lines"])
        words = prose_words(body_text)
        if not words:
            raise ValueError(f"hadith {h['number']} has an empty body")
        out_hadiths.append({
            "number": h["number"], "title": h["title"],
            "body": words, "takhrij": h["takhrij"],
        })
    nums = [h["number"] for h in out_hadiths]
    assert nums == list(range(1, len(nums) + 1)), f"hadith numbers not 1..N: {nums}"
    return {
        "schemaVersion": SCHEMA_VERSION,
        "id": meta.get("id", ""),
        "title": meta.get("title", ""),
        "fullTitle": meta.get("fullTitle", ""),
        "titleLatin": meta.get("titleLatin", ""),
        "author": meta.get("author", ""),
        "meter": meta.get("meter", ""),
        "subject": meta.get("subject", "hadith"),
        "kind": "prose",
        "baytsPerPage": 0,
        "pageCount": 0,
        "baytCount": len(out_hadiths),   # hadith count
        "pages": [],
        "babs": [],
        "hadiths": out_hadiths,
    }


def words_of(hemistich):
    """Split a hemistich into words, honouring colour markers.

    A red span is wrapped in *asterisks*, a blue span in ~tildes~, e.g.
    *الْإِظْهَارُ*  or  ~كَمْ عَسَلْ~ . The markers may fall mid-word so a single
    letter can be coloured inside an otherwise-black word (the farsh رموز), e.g.
    *نَ*مَوْهَا colours only the نَ. Markers are stripped from the stored text.

    Each word is a list of (char, colour) that we merge into runs. A word with
    one run is emitted as {text, norm[, color]}; a word with mixed colours also
    gets {runs: [{text[, color]}, ...]} whose texts concatenate to `text`.
    """
    words = []        # list of list of (char, color)
    current = []      # current word's [(char, color)]
    in_red = False
    in_blue = False

    def flush():
        nonlocal current
        if current:
            words.append(current)
            current = []

    for ch in hemistich:
        if ch == "*":
            in_red = not in_red
            continue
        if ch == "~":
            in_blue = not in_blue
            continue
        if ch.isspace():
            flush()
            continue
        color = "red" if in_red else ("blue" if in_blue else None)
        current.append((ch, color))
    flush()

    out = []
    for chars in words:
        text = "".join(c for c, _ in chars)
        entry = {"text": text, "norm": normalize(text)}

        # Merge consecutive same-colour characters into runs.
        runs = []
        for ch, color in chars:
            if runs and runs[-1][1] == color:
                runs[-1][0] += ch
            else:
                runs.append([ch, color])

        if len(runs) == 1:
            if runs[0][1]:
                entry["color"] = runs[0][1]
        else:
            entry["runs"] = [
                ({"text": t, "color": c} if c else {"text": t}) for t, c in runs
            ]
        out.append(entry)
    return out


# If the final page would hold this few bayts or fewer, fold it onto the
# previous page instead (avoids an orphan line alone on its own page).
ORPHAN_MAX = 2


def build(meta, babs, bayts):
    per_page = int(meta.get("baytsPerPage", "10"))
    total = len(bayts)

    page_count = (total + per_page - 1) // per_page if total else 0
    if page_count >= 2:
        last_count = total - (page_count - 1) * per_page
        if last_count <= ORPHAN_MAX:
            page_count -= 1   # the orphan page merges into the previous one

    out_bayts = []
    row_in_page = {}          # page -> running row count
    for b in bayts:
        n = b["number"]
        page = min((n - 1) // per_page + 1, page_count)
        row = row_in_page.get(page, 0) + 1
        row_in_page[page] = row
        out_bayts.append(
            {
                "number": n,
                "page": page,
                "row": row,
                "babId": b["babId"],
                # Colour markers (* red, ~ blue) only tag words; strip them from
                # the plain display strings. The per-word colour is kept in *Words.
                "sadr": b["sadr"].replace("*", "").replace("~", ""),
                "ajuz": b["ajuz"].replace("*", "").replace("~", ""),
                "sadrWords": words_of(b["sadr"]),
                "ajuzWords": words_of(b["ajuz"]),
            }
        )

    return {
        "schemaVersion": SCHEMA_VERSION,
        "id": meta.get("id", ""),
        "title": meta.get("title", ""),
        "fullTitle": meta.get("fullTitle", ""),
        "titleLatin": meta.get("titleLatin", ""),
        "author": meta.get("author", ""),
        "meter": meta.get("meter", ""),
        # Subject shelf: quran (default) | hadith | seerah | aqeedah | arabic | fiqh
        "subject": meta.get("subject", "quran"),
        "baytsPerPage": per_page,
        "pageCount": page_count,
        "baytCount": len(out_bayts),
        "babs": babs,
        "bayts": out_bayts,
    }


def main(argv):
    if len(argv) != 3:
        print("usage: python3 build_matn.py <source.txt> <output.json>", file=sys.stderr)
        return 2
    src, dst = argv[1], argv[2]
    kind = "poem"
    with open(src, encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s.startswith("%"):
                k, _, v = s[1:].partition("=")
                if k.strip() == "kind":
                    kind = v.strip()
    if kind == "prose":
        meta, hadiths = parse_prose_source(src)
        doc = build_prose(meta, hadiths)
    else:
        meta, babs, bayts = parse_source(src)
        doc = build(meta, babs, bayts)
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    if kind == "prose":
        print(f"wrote {dst}: {doc['baytCount']} hadith (prose)")
    else:
        print(
            f"wrote {dst}: {doc['baytCount']} bayts, {len(doc['babs'])} babs, "
            f"{doc['pageCount']} pages ({doc['baytsPerPage']}/page)"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
