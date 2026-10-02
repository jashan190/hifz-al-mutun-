#!/usr/bin/env python3
"""Convert the Suwaid edition (shatibiyyah_suwaid.json) into the app's canonical
content schema (schemaVersion 2) and write Resources/Content/shatibiyya.json.

Usage:
    python3 Tools/build_suwaid.py shatibiyyah_suwaid.json Resources/Content/shatibiyya.json

The source file is documented in SHATIBIYYAH_DATA.md. We keep only what the app
needs to render and match, dropping `markup` (the app renders from `segments`).

Canonical schema (v2):
    { schemaVersion, id, title, fullTitle, titleLatin, author, meter,
      baytsPerPage, pageCount, baytCount,
      pages: [ { page, items: [ Item ] } ],
      babs:  [ { id, title, startPage } ],          # every heading, for the index
      reviewNotes: [ { page, n, notes: [str] } ] }  # debug-only in the app

    Item (heading): { type:"heading", text, segments:[Seg] }
    Item (bayt):    { type:"bayt", n, sadr:Hemi, ajuz:Hemi }
    Hemi:           { text, segments:[Seg], words:[ {text, normalized} ] }
    Seg:            { text, color } | { footnote }   # color in black|blue|red
"""

import json
import sys

SCHEMA_VERSION = 2

# Library-card metadata (kept identical to the previous Shatibiyyah entry).
META = {
    "id": "shatibiyya",
    "title": "الشاطبية",
    "fullTitle": "حرز الأماني ووجه التهاني",
    "titleLatin": "ash-Shatibiyya",
    "author": "الإمام الشاطبي",
    "meter": "الطويل",
    "baytsPerPage": 10,
}

VALID_COLORS = {"black", "blue", "red"}


def clean_segments(segments, where):
    """Pass segments through, validating shape. Keep text runs (text+color) and
    footnote markers ({footnote}); drop nothing else is expected."""
    out = []
    for seg in segments:
        if "footnote" in seg:
            out.append({"footnote": seg["footnote"]})
        elif "text" in seg:
            color = seg.get("color", "black")
            if color not in VALID_COLORS:
                raise ValueError(f"{where}: unknown colour {color!r}")
            out.append({"text": seg["text"], "color": color})
        else:
            raise ValueError(f"{where}: segment is neither text nor footnote: {seg!r}")
    return out


def clean_hemistich(h, where):
    text = h["text"]
    segs = clean_segments(h["segments"], where)
    # segments (text runs only) must concatenate exactly to text
    cat = "".join(s.get("text", "") for s in segs)
    if cat != text:
        raise ValueError(f"{where}: segments != text\n  text={text!r}\n  segs={cat!r}")
    words = [{"text": w["text"], "normalized": w["normalized"]} for w in h["words"]]
    return {"text": text, "segments": segs, "words": words}


def main(argv):
    if len(argv) != 3:
        print("usage: python3 build_suwaid.py <suwaid.json> <out.json>", file=sys.stderr)
        return 2
    src, dst = argv[1], argv[2]
    doc = json.load(open(src, encoding="utf-8"))

    pages_out = []
    babs = []
    review_notes = []
    bayt_count = 0
    expected_n = 1

    for p in doc["pages"]:
        page_no = p["page"]
        items_out = []
        for it in p["items"]:
            if it["type"] == "heading":
                where = f"page {page_no} heading"
                segs = clean_segments(it["segments"], where)
                text = it["text"]
                cat = "".join(s.get("text", "") for s in segs)
                if cat != text:
                    raise ValueError(f"{where}: segments != text")
                items_out.append({"type": "heading", "text": text, "segments": segs})
                babs.append({
                    "id": f"h{len(babs) + 1}",
                    "title": text,
                    "startPage": page_no,
                })
            elif it["type"] == "bayt":
                n = it["n"]
                if n != expected_n:
                    raise ValueError(f"page {page_no}: bayt number {n} != expected {expected_n}")
                # page N must hold bayts 10N-9..10N
                if (n - 1) // META["baytsPerPage"] + 1 != page_no:
                    raise ValueError(f"bayt {n} is not on its computed page {page_no}")
                expected_n += 1
                bayt_count += 1
                items_out.append({
                    "type": "bayt",
                    "n": n,
                    "sadr": clean_hemistich(it["sadr"], f"p{page_no} b{n} sadr"),
                    "ajuz": clean_hemistich(it["ajuz"], f"p{page_no} b{n} ajuz"),
                })
                if it.get("review_notes"):
                    review_notes.append({"page": page_no, "n": n, "notes": it["review_notes"]})
            else:
                raise ValueError(f"page {page_no}: unknown item type {it['type']!r}")
        pages_out.append({"page": page_no, "items": items_out})

    out = {
        "schemaVersion": SCHEMA_VERSION,
        **{k: META[k] for k in ("id", "title", "fullTitle", "titleLatin", "author", "meter")},
        "baytsPerPage": META["baytsPerPage"],
        "pageCount": len(pages_out),
        "baytCount": bayt_count,
        "pages": pages_out,
        "babs": babs,
        "reviewNotes": review_notes,
    }

    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write("\n")

    print(f"wrote {dst}: {bayt_count} bayts, {len(pages_out)} pages, "
          f"{len(babs)} headings, {len(review_notes)} review notes")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
