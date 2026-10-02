#!/usr/bin/env python3
"""Render PDF pages to PNG images for visual verification of the transcription.

Usage:
    python3 Tools/render_pages.py "source/Tuhfah + Jazariyya.pdf" 10 15 out_dir

Renders pages 10..15 into out_dir as page-010.png etc. Use these images to
check, bayt by bayt, that the transcribed text matches the PDF before trusting
the generated JSON.

Needs poppler's pdftoppm (brew install poppler).
"""

import shutil
import subprocess
import sys
from pathlib import Path


def main(argv):
    if len(argv) not in (4, 5):
        print("usage: python3 render_pages.py <file.pdf> <first> <last> [out_dir]",
              file=sys.stderr)
        return 2
    if shutil.which("pdftoppm") is None:
        print("missing pdftoppm — install with: brew install poppler", file=sys.stderr)
        return 3

    path, first, last = argv[1], int(argv[2]), int(argv[3])
    out_dir = Path(argv[4]) if len(argv) == 5 else Path("Tools/render")
    out_dir.mkdir(parents=True, exist_ok=True)
    prefix = str(out_dir / "page")

    subprocess.run(
        ["pdftoppm", "-png", "-r", "140",
         "-f", str(first), "-l", str(last), path, prefix],
        check=True,
    )
    print(f"rendered pages {first}..{last} of {path} -> {out_dir}/page-*.png")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
