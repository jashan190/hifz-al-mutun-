#!/usr/bin/env python3
"""Report whether a PDF has a usable text layer or is scanned images.

Usage:
    python3 Tools/inspect_pdf.py "source/Tuhfah + Jazariyya.pdf"

Needs the poppler command-line tools (install once with: brew install poppler).
It runs pdfinfo / pdffonts / pdftotext and prints a plain-language verdict per
page so you can decide, for each matn, whether the text can be extracted or
whether it must be transcribed from a digital edition and verified by eye.
"""

import shutil
import subprocess
import sys

TOOLS = ["pdfinfo", "pdffonts", "pdftotext"]


def have_tools():
    missing = [t for t in TOOLS if shutil.which(t) is None]
    if missing:
        print(
            "missing poppler tools: " + ", ".join(missing) +
            "\ninstall with: brew install poppler",
            file=sys.stderr,
        )
        return False
    return True


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def page_count(path):
    for line in run(["pdfinfo", path]).splitlines():
        if line.startswith("Pages:"):
            return int(line.split(":", 1)[1].strip())
    return 0


def main(argv):
    if len(argv) != 2:
        print("usage: python3 inspect_pdf.py <file.pdf>", file=sys.stderr)
        return 2
    if not have_tools():
        return 3

    path = argv[1]
    pages = page_count(path)
    print(f"=== {path} ===")
    print(f"pages: {pages}")

    fonts = run(["pdffonts", path]).strip().splitlines()
    has_fonts = len(fonts) > 2  # header is 2 lines
    print(f"embedded/real fonts listed: {'yes' if has_fonts else 'no'}")

    # Sample text density across the document.
    text_pages = 0
    sampled = 0
    for p in range(1, pages + 1):
        txt = run(["pdftotext", "-f", str(p), "-l", str(p), path, "-"])
        chars = len("".join(txt.split()))
        sampled += 1
        if chars > 20:
            text_pages += 1

    print(f"pages with real extractable text (>20 chars): {text_pages}/{sampled}")

    if text_pages == 0 and not has_fonts:
        verdict = "SCANNED IMAGES — no text layer. Transcribe from a digital edition; use the PDF only for layout/verification."
    elif text_pages == 0 and has_fonts:
        verdict = ("VECTOR TEXT but NOT EXTRACTABLE (legacy encoding / no Unicode map). "
                   "Renders fine to images, but copy/extract yields nothing usable. "
                   "Transcribe from a digital edition; verify by eye against rendered pages.")
    elif text_pages < sampled * 0.5:
        verdict = "PARTIAL text layer — some pages extract, many do not. Treat as unreliable; verify everything."
    else:
        verdict = "USABLE text layer — extraction looks viable (still spot-check the Arabic)."

    print(f"verdict: {verdict}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
