#!/usr/bin/env python3
"""Validate a built matn JSON file.

Usage:
    python3 Tools/validate_matn.py Resources/Content/tuhfa.json

Two layouts are understood: the bayt list (schemaVersion 1: tuhfa, jazariyya)
and the page list (schemaVersion 2: shatibiyya, laid out page by page as in the
printed book). Any other schemaVersion fails.

Checks (schemaVersion 1):
  1. bayt numbers are continuous 1..N with no gaps or duplicates
  2. every bayt has a non-empty sadr and ajuz (and matching word lists)
  3. page/row match the declared baytsPerPage
  4. babs are contiguous, non-overlapping, and cover every bayt exactly once
  5. declared baytCount / pageCount agree with the actual bayts

Checks (schemaVersion 2):
  1. pages are numbered 1..pageCount in order; items are bayts or headings
  2. bayt numbers run 1..N across pages with no gaps or duplicates
  3. every half has text; its text runs concatenate to that text; its word
     list matches the words of the text (stand-alone punctuation aside), and
     each word normalizes to something
  4. no page holds more than baytsPerPage + 2 bayts
  5. babs start on pages in order, each where a heading with its title stands,
     and headings and babs are one-to-one
  6. review notes point at a bayt that exists on that page
  7. declared baytCount / pageCount agree with the actual content

Exits non-zero if any check fails, so it can gate the pipeline.
"""

import json
import sys


def validate(doc):
    errors = []
    warnings = []

    bayts = doc.get("bayts", [])
    per_page = doc.get("baytsPerPage", 10)

    # 1. continuous numbering 1..N
    numbers = [b["number"] for b in bayts]
    expected = list(range(1, len(bayts) + 1))
    if numbers != expected:
        # find the first point of divergence for a helpful message
        for i, (got, exp) in enumerate(zip(numbers, expected)):
            if got != exp:
                errors.append(
                    f"bayt numbering breaks at position {i + 1}: "
                    f"expected {exp}, got {got}"
                )
                break
        else:
            errors.append(
                f"bayt count mismatch: {len(numbers)} bayts but numbers go to "
                f"{numbers[-1] if numbers else 0}"
            )

    # 2. both halves present + word lists non-empty and consistent
    for b in bayts:
        n = b["number"]
        if not b.get("sadr", "").strip():
            errors.append(f"bayt {n}: empty sadr")
        if not b.get("ajuz", "").strip():
            errors.append(f"bayt {n}: empty ajuz")
        if len(b.get("sadrWords", [])) != len(b.get("sadr", "").split()):
            errors.append(f"bayt {n}: sadrWords count != words in sadr")
        if len(b.get("ajuzWords", [])) != len(b.get("ajuz", "").split()):
            errors.append(f"bayt {n}: ajuzWords count != words in ajuz")
        for side in ("sadrWords", "ajuzWords"):
            for w in b.get(side, []):
                if not w.get("norm", ""):
                    warnings.append(
                        f"bayt {n}: word {w.get('text')!r} normalizes to empty"
                    )

    # 3. pages are contiguous 1..pageCount; rows run 1..k within each page; and no
    #    page holds more than per_page + 2 bayts (the orphan-merge allowance).
    pages_in_order = [b.get("page") for b in bayts]
    distinct_pages = sorted(set(pages_in_order))
    if distinct_pages and distinct_pages != list(range(1, distinct_pages[-1] + 1)):
        errors.append(f"pages are not contiguous from 1: {distinct_pages}")
    # page must not decrease as bayt number increases
    for i in range(1, len(pages_in_order)):
        if pages_in_order[i] < pages_in_order[i - 1]:
            errors.append(
                f"bayt {bayts[i]['number']}: page {pages_in_order[i]} goes backwards"
            )
            break
    from collections import Counter
    page_counts = Counter(pages_in_order)
    for p, count in page_counts.items():
        if count > per_page + 2:
            errors.append(f"page {p} holds {count} bayts (> {per_page} + 2)")
    # rows 1..k within each page, in order
    seen_rows = {}
    for b in bayts:
        p = b.get("page")
        expected_row = seen_rows.get(p, 0) + 1
        seen_rows[p] = expected_row
        if b.get("row") != expected_row:
            errors.append(
                f"bayt {b['number']}: row {b.get('row')} != expected {expected_row} on page {p}"
            )

    # 4. babs contiguous and covering every bayt once
    babs = doc.get("babs", [])
    covered = []
    last_end = 0
    for bab in babs:
        s, e = bab.get("startBayt"), bab.get("endBayt")
        if s is None or e is None:
            errors.append(f"bab {bab.get('id')!r}: missing start/end")
            continue
        if s != last_end + 1:
            errors.append(
                f"bab {bab.get('id')!r}: starts at {s}, expected {last_end + 1} "
                f"(gap or overlap)"
            )
        if e < s:
            errors.append(f"bab {bab.get('id')!r}: end {e} before start {s}")
        last_end = e
        covered.extend(range(s, e + 1))
    if bayts and last_end != len(bayts):
        errors.append(
            f"babs cover up to bayt {last_end}, but there are {len(bayts)} bayts"
        )

    # 5. declared counts
    if doc.get("baytCount") != len(bayts):
        errors.append(
            f"baytCount {doc.get('baytCount')} != actual {len(bayts)}"
        )
    actual_pages = max(pages_in_order) if pages_in_order else 0
    if doc.get("pageCount") != actual_pages:
        errors.append(
            f"pageCount {doc.get('pageCount')} != actual max page {actual_pages}"
        )

    return errors, warnings


def validate_pages(doc):
    errors = []
    warnings = []
    pages = doc.get("pages", [])
    per_page = doc.get("baytsPerPage", 10)

    # 1. page numbering and item types
    for i, page in enumerate(pages):
        if page.get("page") != i + 1:
            errors.append(f"page at position {i + 1} is numbered {page.get('page')}")
        for item in page.get("items", []):
            if item.get("type") not in ("bayt", "heading"):
                errors.append(f"page {page.get('page')}: unknown item type {item.get('type')!r}")

    bayts = [(page.get("page"), item) for page in pages
             for item in page.get("items", []) if item.get("type") == "bayt"]
    headings = [(page.get("page"), item.get("text")) for page in pages
                for item in page.get("items", []) if item.get("type") == "heading"]

    # 2. continuous numbering
    numbers = [b.get("n") for _, b in bayts]
    for i, n in enumerate(numbers):
        if n != i + 1:
            errors.append(f"bayt numbering breaks at position {i + 1}: expected {i + 1}, got {n}")
            break

    # 3. halves: text, runs, words
    for page_no, b in bayts:
        n = b.get("n")
        for side in ("sadr", "ajuz"):
            half = b.get(side) or {}
            text = half.get("text", "")
            if not text.strip():
                errors.append(f"bayt {n}: empty {side}")
                continue
            runs = "".join(seg.get("text", "") for seg in half.get("segments", [])
                           if "footnote" not in seg)
            if runs != text:
                errors.append(f"bayt {n} {side}: text runs don't concatenate to the text")
            words = half.get("words", [])
            # Stand-alone punctuation ("،") isn't a word.
            spoken = [t for t in text.split() if any(c.isalpha() for c in t)]
            if [w.get("text") for w in words] != spoken:
                errors.append(f"bayt {n} {side}: word list != words of the text")
            for w in words:
                if not w.get("normalized"):
                    warnings.append(f"bayt {n} {side}: word {w.get('text')!r} normalizes to empty")

    # 4. page capacity
    from collections import Counter
    for p, count in Counter(p for p, _ in bayts).items():
        if count > per_page + 2:
            errors.append(f"page {p} holds {count} bayts (> {per_page} + 2)")

    # 5. babs line up with headings
    babs = doc.get("babs", [])
    last = 0
    for bab in babs:
        start = bab.get("startPage")
        if not isinstance(start, int) or not 1 <= start <= len(pages):
            errors.append(f"bab {bab.get('id')!r}: startPage {start!r} out of range")
            continue
        if start < last:
            errors.append(f"bab {bab.get('id')!r}: starts on page {start}, before the previous bab")
        last = start
        if (start, bab.get("title")) not in headings:
            errors.append(f"bab {bab.get('id')!r}: no heading {bab.get('title')!r} on page {start}")
    if len(babs) != len(headings):
        errors.append(f"{len(babs)} babs but {len(headings)} headings")

    # 6. review notes
    on_page = {(p, b.get("n")) for p, b in bayts}
    for note in doc.get("reviewNotes", []):
        if (note.get("page"), note.get("n")) not in on_page:
            errors.append(f"review note for bayt {note.get('n')} on page {note.get('page')}: no such bayt there")

    # 7. declared counts
    if doc.get("baytCount") != len(bayts):
        errors.append(f"baytCount {doc.get('baytCount')} != actual {len(bayts)}")
    if doc.get("pageCount") != len(pages):
        errors.append(f"pageCount {doc.get('pageCount')} != actual {len(pages)} pages")

    return errors, warnings, len(bayts)


def main(argv):
    if len(argv) != 2:
        print("usage: python3 validate_matn.py <matn.json>", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        doc = json.load(f)

    version = doc.get("schemaVersion", 1)
    if version == 1:
        errors, warnings = validate(doc)
        bayt_count = len(doc.get("bayts", []))
    elif version == 2:
        errors, warnings, bayt_count = validate_pages(doc)
    else:
        print(f"unsupported schemaVersion {version!r} (expected 1 or 2)")
        return 1

    title = doc.get("titleLatin") or doc.get("id")
    print(f"Validating {title} (schemaVersion {version}): {bayt_count} bayts, "
          f"{len(doc.get('babs', []))} babs, {doc.get('pageCount')} pages")

    for w in warnings:
        print(f"  warning: {w}")
    for e in errors:
        print(f"  ERROR: {e}")

    if errors:
        print(f"FAILED with {len(errors)} error(s)")
        return 1
    print("OK — all checks passed" + (f" ({len(warnings)} warning(s))" if warnings else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
