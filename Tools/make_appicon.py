#!/usr/bin/env python3
"""Generate a 1024x1024 placeholder app icon for Hifz al-Mutun.

Deep manuscript-green field with a cream eight-point star (rub el hizb) and a
pierced roundel centre — on-brand with the app's parchment/green palette.
Opaque RGB (no alpha): the App Store rejects icons with transparency.

    python3 Tools/make_appicon.py
Writes Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""
import math
import os
from PIL import Image, ImageDraw

SCALE = 4                      # supersample, then downscale for smooth edges
S = 1024 * SCALE
c = S / 2

GREEN      = (15, 61, 51)      # #0F3D33 field
GREEN_SOFT = (20, 70, 58)      # #14463A inner disc
CREAM      = (243, 233, 207)   # #F3E9CF star
GOLD       = (201, 169, 106)   # #C9A96A accent ring

img = Image.new("RGB", (S, S), GREEN)
d = ImageDraw.Draw(img)

# Soft inner disc for depth.
disc_r = 0.40 * S
d.ellipse([c - disc_r, c - disc_r, c + disc_r, c + disc_r], fill=GREEN_SOFT)

# Thin gold ring just outside the star.
ring_r = 0.345 * S
d.ellipse([c - ring_r, c - ring_r, c + ring_r, c + ring_r],
          outline=GOLD, width=int(6 * SCALE))

# Eight-point star = two congruent squares, one rotated 45 degrees.
r = 0.235 * S
R = r * math.sqrt(2)
sq1 = [(c - r, c - r), (c + r, c - r), (c + r, c + r), (c - r, c + r)]
sq2 = [(c, c - R), (c + R, c), (c, c + R), (c - R, c)]
d.polygon(sq1, fill=CREAM)
d.polygon(sq2, fill=CREAM)

# Pierced roundel centre (manuscript style).
hole_r = 0.075 * S
d.ellipse([c - hole_r, c - hole_r, c + hole_r, c + hole_r], fill=GREEN)
d.ellipse([c - hole_r, c - hole_r, c + hole_r, c + hole_r],
          outline=GOLD, width=int(5 * SCALE))

img = img.resize((1024, 1024), Image.LANCZOS)
out = os.path.join(os.path.dirname(__file__), "..",
                   "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
img.save(os.path.abspath(out), "PNG")
print("wrote", os.path.abspath(out))
