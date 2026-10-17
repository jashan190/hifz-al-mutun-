import json
def half_lines(path):
    """(bayt, half, text) for every half-line, whichever layout the matn uses."""
    m = json.load(open(path))
    if "pages" in m:
        for p in m["pages"]:
            for it in p["items"]:
                if it.get("type") == "bayt":
                    for h in ("sadr", "ajuz"): yield it["n"], h, it[h]["text"]
    else:
        for b in m["bayts"]:
            for h in ("sadr", "ajuz"): yield b["number"], h, b[h]
