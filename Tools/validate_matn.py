#!/usr/bin/env python3
"""Validate a built matn JSON file.

Usage:
    python3 Tools/validate_matn.py Resources/Content/tuhfa.json

Checks:
  1. bayt numbers are continuous 1..N with no gaps or duplicates
  2. every bayt has a non-empty sadr and ajuz (and matching word lists)
  3. page/row match the declared baytsPerPage
  4. babs are contiguous, non-overlapping, and cover every bayt exactly once
  5. declared baytCount / pageCount agree with the actual bayts

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


def main(argv):
    if len(argv) != 2:
        print("usage: python3 validate_matn.py <matn.json>", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        doc = json.load(f)

    errors, warnings = validate(doc)

    title = doc.get("titleLatin") or doc.get("id")
    print(f"Validating {title}: {len(doc.get('bayts', []))} bayts, "
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
