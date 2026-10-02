# Tools — content pipeline

Python scripts that run on your Mac (not in the app) to turn the PDFs and
hand-verified transcriptions into the bundled content JSON.

One-time setup (already done on this machine):

```sh
brew install poppler        # pdfinfo, pdffonts, pdftotext, pdftoppm, pdfimages
```

No third-party Python packages are needed — everything uses the standard library.

## Scripts

| script             | what it does |
|--------------------|--------------|
| `inspect_pdf.py`   | Reports whether a PDF has a usable text layer or is scanned. |
| `render_pages.py`  | Renders PDF page ranges to PNGs so you can verify text by eye. |
| `normalize.py`     | Shared Arabic normalization (also runnable for a self-check). |
| `build_matn.py`    | Builds a matn JSON from a `sources/<id>.txt` transcription. |
| `validate_matn.py` | Validates a built JSON (numbering, halves, pages, babs). |

## Typical flow for a new matn

```sh
# 1. Is the PDF text usable?
python3 Tools/inspect_pdf.py "source/Tuhfah + Jazariyya.pdf"

# 2. Render the poem pages to check the transcription against.
python3 Tools/render_pages.py "source/Tuhfah + Jazariyya.pdf" 10 15 Tools/render

# 3. Hand-verify text into Tools/sources/<id>.txt  (see tuhfa.txt for the format)

# 4. Build and validate.
python3 Tools/build_matn.py Tools/sources/tuhfa.txt Resources/Content/tuhfa.json
python3 Tools/validate_matn.py Resources/Content/tuhfa.json
```

## Why the text is transcribed, not extracted

Both source PDFs were inspected (`inspect_pdf.py`):

- **Shatibiyyah** (`منظومة_حرز_الأماني…`) — fully scanned images, no text layer.
- **Tuhfah + Jazariyya** — vector text, but drawn with a legacy Windows-1256
  encoding and no Unicode mapping, so copy/extract yields nothing usable (the
  only pages that extract are the isnad pages at the end).

So for every matn the text comes from a trusted vocalized edition and is
verified bayt-by-bayt against the rendered PDF pages. The PDF is used for
verification and ordering; the 10-bayts-per-page layout is this project's own.
